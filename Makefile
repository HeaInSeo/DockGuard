# Makefile

OPA      ?= opa
CONFTEST ?= conftest

POLICY_DIRS  := policy/dockerfile policy/security policy/genomics
EXAMPLES_DIR := examples
BUILD_DIR    := build
POLICIES_JSON := $(BUILD_DIR)/policies.json

# WASM bundle (S1). Entrypoint order is ABI: NodeKit evaluates entrypoint index 0
# (architecture §2.29.1), so this list is ordered and must not be reordered.
WASM_ENTRYPOINTS := dockerfile/multistage/deny
WASM             := $(BUILD_DIR)/dockguard.wasm
PROVENANCE       := $(BUILD_DIR)/provenance.json

.PHONY: all fmt fmt-check test-rego test-conftest test-conftest-strict test policies-json wasm bundle

all: test

# Rego 파일 포맷/린트 확인 (policy 전체 하위)
fmt:
	@for d in $(POLICY_DIRS); do \
	    echo "==> opa fmt -l $$d"; \
	    $(OPA) fmt -l $$d; \
	done

# CI: 포맷되지 않은 Rego 파일이 있으면 실패
fmt-check:
	$(OPA) fmt --fail -d policy

# 1) OPA 유닛 테스트: 각 policy 디렉토리 단위로 실행
test-rego:
	@for d in $(POLICY_DIRS); do \
	    echo "==> opa test $$d"; \
	    $(OPA) test $$d || exit 1; \
	done

# 2) Conftest 통합 린트: conftest.toml 기준 (policy/dockerfile, security, genomics 모두 포함)
# Dockerfile.bad 예시 파일에서 위반이 검출되는 것이 정상이므로 --no-fail 사용
test-conftest:
	@echo "==> conftest test $(EXAMPLES_DIR) (conftest.toml 기준)"
	@$(CONFTEST) test $(EXAMPLES_DIR) \
	  --parser dockerfile \
	  --rego-version v1 \
	  --no-fail

# CI: Dockerfile.bad 는 반드시 위반을 내야 한다. 위반이 없거나(exit 0) conftest 가
# 정책을 로드하지 못하면(FAIL 없음) 실패한다.
test-conftest-strict:
	@set +e; out="$$($(CONFTEST) test $(EXAMPLES_DIR)/Dockerfile.bad --parser dockerfile --rego-version v1 --no-color 2>&1)"; rc=$$?; set -e; \
	echo "$$out"; \
	if [ $$rc -eq 0 ]; then echo "conftest: Dockerfile.bad passed but must be denied"; exit 1; fi; \
	if ! echo "$$out" | grep -q '^FAIL'; then echo "conftest: exit $$rc without policy failures"; exit 1; fi; \
	echo "conftest: Dockerfile.bad denied as expected (exit $$rc)"

# 3) 전체 테스트 (fmt → opa test)
# conftest 통합 테스트는 bad 파일이 위반을 내는 것이 정상이므로 별도 타겟으로 분리함
test: fmt test-rego
	@echo "All OPA policy tests passed!"

# 4) policies.json 생성: # METADATA 어노테이션 → JSON 추출
# 생성된 파일은 NodeVault assets/policy/policies.json 으로 배포한다.
# Note: OPA WASM 빌드(opa build -t wasm)는 CGo 가 필요한 별도 환경에서 수행한다.
policies-json: $(POLICIES_JSON)

$(POLICIES_JSON): $(shell find policy -name '*.rego' ! -name '*_test.rego')
	@mkdir -p $(BUILD_DIR)
	$(OPA) inspect --annotations --format json policy/ | jq '[.annotations[] | select(.annotations.custom.rule_id != null) | {rule_id: .annotations.custom.rule_id, title: .annotations.title, description: .annotations.description}] | unique_by(.rule_id) | sort_by(.rule_id)' > $(POLICIES_JSON)
	@echo "Generated $(POLICIES_JSON)"

# 5) WASM 빌드: 정책 소스(*_test.rego 제외) → OPA wasm, 순서 고정 entrypoint
wasm:
	@rm -rf $(BUILD_DIR)/wasm && mkdir -p $(BUILD_DIR)/wasm
	$(OPA) build -t wasm $(addprefix -e ,$(WASM_ENTRYPOINTS)) --ignore '*_test.rego' -o $(BUILD_DIR)/bundle.tar.gz policy/
	tar -xzf $(BUILD_DIR)/bundle.tar.gz -C $(BUILD_DIR)/wasm
	cp $(BUILD_DIR)/wasm/policy.wasm $(WASM)

# 6) 배포 단위: wasm + policies.json + provenance.json + SHA256SUMS
bundle: wasm policies-json
	jq -n \
	  --arg commit "$$(git rev-parse HEAD)" \
	  --arg opa "$$($(OPA) version | sed -n 's/^Version: //p')" \
	  --arg wasm_sha256 "$$(sha256sum $(WASM) | cut -d' ' -f1)" \
	  --arg policies_sha256 "$$(sha256sum $(POLICIES_JSON) | cut -d' ' -f1)" \
	  --argjson entrypoints '$(shell printf '%s\n' $(WASM_ENTRYPOINTS) | jq -Rsc 'split("\n")[:-1]')' \
	  --argjson tested '$(shell printf '%s\n' $(POLICY_DIRS) | jq -Rsc 'split("\n")[:-1]')' \
	  '{source_commit: $$commit, opa_version: $$opa, target: "wasm", entrypoints: $$entrypoints, wasm_policy_scope: "only rules reachable from entrypoints", tested_policy_dirs: $$tested, wasm_sha256: $$wasm_sha256, policies_json_sha256: $$policies_sha256}' \
	  > $(PROVENANCE)
	cd $(BUILD_DIR) && sha256sum dockguard.wasm policies.json provenance.json > SHA256SUMS
	@cat $(PROVENANCE) $(BUILD_DIR)/SHA256SUMS
