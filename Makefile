# Makefile

OPA      ?= opa
CONFTEST ?= conftest

POLICY_DIRS := policy/dockerfile policy/security policy/genomics
EXAMPLES_DIR := examples

.PHONY: all fmt test-rego test-conftest test

all: test

# Rego 파일 포맷/린트 확인 (policy 전체 하위)
fmt:
	@for d in $(POLICY_DIRS); do \
	    echo "==> opa fmt -l $$d"; \
	    $(OPA) fmt -l $$d; \
	done

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

# 3) 전체 테스트 (fmt → opa test)
# conftest 통합 테스트는 bad 파일이 위반을 내는 것이 정상이므로 별도 타겟으로 분리함
test: fmt test-rego
	@echo "All OPA policy tests passed!"
