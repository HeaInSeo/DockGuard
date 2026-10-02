# DockGuard

## Install Opa CLI
- https://www.openpolicyagent.org/docs/latest/#running-opa  

## Install conftest 
- https://www.conftest.dev/install/  


## Makefile 구조

```makefile
OPA      ?= opa
CONFTEST ?= conftest

POLICY_DIR      := policy/dockerfile
OPA_TEST_FILES  := $(wildcard $(POLICY_DIR)/*_test.rego)

.PHONY: all fmt test-rego test-conftest test

all: test

# Rego 파일 포맷/린트 확인 (policy 하위 모든 .rego)
fmt:
	@echo "==> opa fmt -l $(POLICY_DIR)"
	@$(OPA) fmt -l $(POLICY_DIR)

# 1) OPA 유닛 테스트: POLICY_DIR 아래 모든 _test.rego 파일
test-rego: $(OPA_TEST_FILES)
	@echo "==> opa test $(POLICY_DIR)"
	@$(OPA) test $(POLICY_DIR)

# 2) Conftest 통합 린트: POLICY_DIR 전체
test-conftest:
	@echo "==> conftest test --policy $(POLICY_DIR)"
	@$(CONFTEST) test --policy $(POLICY_DIR)

# 3) 전체 테스트 (fmt → opa test → conftest test)
test: fmt test-rego test-conftest
	@echo "✅ All policy tests passed!"
```


## Usage

### 전체 검사

```bash
make test
```

* `fmt` → `test-rego` → `test-conftest` 순서로 실행됩니다.

### 개별 단계 실행

* 포맷/린트 검사만:

  ```bash
  make fmt
  ```

* OPA 유닛 테스트만:

  ```bash
  make test-rego
  ```

* Conftest 린트만:

  ```bash
  make test-conftest
  ```

### Release 패키징 (S2)

`release/pin.json`이 릴리스할 정책 source commit, OPA 버전, 순서 고정 entrypoint, 기대 sha256을 고정한다.
릴리스 wasm은 tag commit의 `policy/`가 아니라 이 pin의 source commit에서 다시 빌드한다.

```bash
bash scripts/package-release.sh v1.0.0 dist   # pin source에서 재빌드 → digest/provenance 검증 → 자산 생성
bash scripts/verify-release.sh dist v1.0.0     # 자산 누락·추가, SHA256SUMS, pin/provenance 불일치를 거부
bash scripts/test-release-negative.sh          # 잘못된 입력·변조 자산이 거부되는지 확인
```

자산은 `dockguard.wasm`, `policies.json`, `provenance.json`(S1, policy source 기준), `release-provenance.json`(release version, policy source commit, packaging commit, OPA binary sha256, 자산 digest), `SHA256SUMS`이다.
`vMAJOR.MINOR.PATCH` tag push 시 `.github/workflows/release.yml`이 같은 검증 후 GitHub Release를 만든다. tag 생성 자체는 별도 릴리스 판정이다.

### TODO 실제 dockerfile 검사 및 conda, 기존 있는 여러 dockerfile 등 적용.
- 먼저 rego 완성한다.
- 이후 dockerfile parser 적용하고, 세부적인것을 적용한다. 메뉴얼 작성이라던지 이런것들.
- bio 부분 확장해서 적용한다.
- conftest 사용할지 말지 고민하자. 지금 필요 없을 듯 한데 조금더 고민해보자. rego 코드가 더 지저분해지는 거 같다.  