# policy/security/security.rego
package dockerfile.security

import future.keywords.in

# --- normalize helper (multistage.rego와 동일한 구조) ---
args_or_empty(inst) := a if {
	a := inst.Value
} else := a if {
	a := []
}

raw_or_empty(inst) := r if {
	r := inst.Raw
} else := r if {
	r := ""
}

normalize(inst) := res if {
	inst.Cmd
	res := {
		"cmd": lower(inst.Cmd),
		"args": args_or_empty(inst),
		"raw": raw_or_empty(inst),
	}
} else := res if {
	inst.Instruction
	res := {
		"cmd": lower(inst.Instruction),
		"args": args_or_empty(inst),
		"raw": raw_or_empty(inst),
	}
}

# helper: USER 명령어가 존재하는지
has_user_instruction if {
	some inst in input
	n := normalize(inst)
	n.cmd == "user"
}

# --- DSF001a: USER 명령어 자체가 없음 ---
# USER 명령어가 없으면 컨테이너가 root로 실행된다.
deny contains msg if {
	not has_user_instruction
	msg := "DSF001: Dockerfile에 USER 명령어가 없습니다. root 권한 실행을 방지하려면 비루트 사용자를 지정하세요. (예: USER 1000 또는 USER nonroot)"
}

# --- DSF001b: USER root / USER 0 명시적 사용 금지 ---
deny contains msg if {
	some inst in input
	n := normalize(inst)
	n.cmd == "user"
	regex.match(`(?i)^USER\s+(root|0)(\s|$)`, n.raw)
	msg := "DSF001: USER root 또는 USER 0은 허용되지 않습니다. 비루트 사용자를 지정하세요. (예: USER 1000 또는 USER nonroot)"
}

# --- DSF002: ENV에 비밀 키 패턴 포함 금지 ---
# 변수명에 PASSWORD, SECRET, API_KEY, TOKEN, PASSWD 가 포함된 ENV는 차단한다.
# 비밀 값은 빌드 시점에 이미지에 포함되어서는 안 된다.
deny contains msg if {
	some inst in input
	n := normalize(inst)
	n.cmd == "env"
	regex.match(`(?i)\b(PASSWORD|SECRET|API_KEY|TOKEN|PASSWD)\b`, n.raw)
	msg := sprintf("DSF002: ENV 명령어에 비밀 키 패턴이 포함된 변수명이 있습니다: %q. 비밀 값은 Dockerfile에 하드코딩하지 마세요.", [n.raw])
}

# --- DSF003: ADD 명령어 원격 URL 사용 금지 ---
# ADD <url> 형태는 빌드 시점 외부 의존성을 도입하여 재현성을 해친다.
# 파일 다운로드는 RUN wget 또는 RUN curl 에서 명시적으로 처리해야 한다.
deny contains msg if {
	some inst in input
	n := normalize(inst)
	n.cmd == "add"
	regex.match(`\bhttps?://`, n.raw)
	msg := sprintf("DSF003: ADD 명령어에서 원격 URL 사용은 금지됩니다. RUN curl 또는 RUN wget을 사용하세요: %q", [n.raw])
}
