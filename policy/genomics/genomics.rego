# policy/genomics/genomics.rego
package dockerfile.genomics

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

# --- DGF001: conda / mamba / micromamba install 버전 고정 강제 ---
# `conda install bwa` 형태는 차단한다.
# 허용: `conda install bwa=0.7.17`, `conda install -f env.yml`, `conda install --file env.yml`
deny contains msg if {
	some inst in input
	n := normalize(inst)
	n.cmd == "run"
	regex.match(`\b(conda|mamba|micromamba)\s+install\b`, n.raw)
	not conda_install_pinned_or_file(n.raw)
	msg := sprintf("DGF001: RUN 내 conda/mamba/micromamba install에는 버전 고정(패키지=버전) 또는 파일 지정(-f/--file)이 필요합니다: %q", [n.raw])
}

# 버전 고정 또는 파일 지정이 있으면 허용
conda_install_pinned_or_file(raw) if {
	# 버전 고정: 패키지명=버전 (예: bwa=0.7.17=h...) 형태가 하나라도 있으면 OK
	regex.match(`\b\w[\w.-]+=\S+`, raw)
} else if {
	# 파일 지정: -f 또는 --file 플래그
	regex.match(`\s(-f|--file)\s`, raw)
}

# --- DGF002: pip install 버전 고정 강제 ---
# `pip install numpy` 형태는 차단한다.
# 허용: `pip install numpy==1.24.0`, `pip install -r requirements.txt`, `pip install --requirement requirements.txt`
deny contains msg if {
	some inst in input
	n := normalize(inst)
	n.cmd == "run"
	regex.match(`\bpip[0-9]?\s+install\b`, n.raw)
	not pip_install_pinned_or_requirements(n.raw)
	msg := sprintf("DGF002: RUN 내 pip install에는 버전 지정(==version) 또는 requirements 파일(-r/--requirement)이 필요합니다: %q", [n.raw])
}

# 버전 고정 또는 requirements 파일 지정이 있으면 허용
pip_install_pinned_or_requirements(raw) if {
	# 버전 지정: ==, >=, <=, ~=, != 연산자
	regex.match(`[=<>!~]=`, raw)
} else if {
	# requirements 파일: -r 또는 --requirement
	regex.match(`\s(-r|--requirement)\s`, raw)
} else if {
	# .txt 파일 직접 참조
	regex.match(`requirements.*\.txt`, raw)
}
