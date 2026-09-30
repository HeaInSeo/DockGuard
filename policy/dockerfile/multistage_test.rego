# policy/dockerfile/multistage_test.rego
package dockerfile.multistage

import data.dockerfile.multistage

# --- 정상 케이스: 정확히 한 번의 FROM + AS builder ---
test_builder_only_ok if {
	testInput := [{"Cmd": "from", "Raw": "FROM ubuntu:20.04 AS builder"}]

	# deny 집합이 비어 있어야 정상
	data.dockerfile.multistage.deny with input as testInput == []
}

# --- DFM001: FROM이 1개가 아니면 에러 ---
test_dfm001_too_many_from if {
	testInput := [
		{"Cmd": "from", "Raw": "FROM ubuntu:20.04 AS builder"},
		{"Cmd": "from", "Raw": "FROM alpine:3.14 AS builder"},
	]

	# denyMsgs 변수에 테스트용 input으로 평가한 deny 집합 바인딩
	denyMsgs := data.dockerfile.multistage.deny with input as testInput

	# 특정 코드가 포함된 메시지를 안전하게 바인딩
	msg := denyMsgs[_]
	startswith(msg, "DFM001")
}

# --- DFM002: AS builder 별칭 누락 ---
test_dfm002_missing_builder_alias if {
	testInput := [{"Cmd": "from", "Raw": "FROM ubuntu:20.04"}]
	denyMsgs := data.dockerfile.multistage.deny with input as testInput
	msg := denyMsgs[_]
	startswith(msg, "DFM002")
}

# --- DFM003: 최종 스테이지 정의 금지 ---
test_dfm003_forbidden_final_stage if {
	testInput := [
		{"Cmd": "from", "Raw": "FROM ubuntu:20.04 AS builder"},
		{"Cmd": "from", "Raw": "FROM busybox:latest AS final"},
	]
	denyMsgs := data.dockerfile.multistage.deny with input as testInput
	msg := denyMsgs[_]
	startswith(msg, "DFM003")
}

# --- DFM004: COPY --from=builder 사용 금지 ---
test_dfm004_forbidden_copy_from if {
	testInput := [
		{"Cmd": "from", "Raw": "FROM ubuntu:20.04 AS builder"},
		{"Cmd": "copy", "Value": ["--from=builder", "/src", "/dest"], "Raw": "COPY --from=builder /src /dest"},
	]
	denyMsgs := data.dockerfile.multistage.deny with input as testInput
	msg := denyMsgs[_]
	startswith(msg, "DFM004")
}
