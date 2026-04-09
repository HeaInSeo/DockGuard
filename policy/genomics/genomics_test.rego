# policy/genomics/genomics_test.rego
package dockerfile.genomics

# ─── DGF001: conda/mamba/micromamba install 버전 고정 강제 ──────────────────

# conda install bwa (버전 없음) → DGF001
test_dgf001_conda_no_version if {
	testInput := [
		{"Cmd": "from", "Raw": "FROM ubuntu:22.04 AS builder"},
		{"Cmd": "run", "Raw": "RUN conda install bwa"},
	]
	denyMsgs := data.dockerfile.genomics.deny with input as testInput
	msg := denyMsgs[_]
	startswith(msg, "DGF001")
}

# mamba install samtools (버전 없음) → DGF001
test_dgf001_mamba_no_version if {
	testInput := [
		{"Cmd": "from", "Raw": "FROM ubuntu:22.04 AS builder"},
		{"Cmd": "run", "Raw": "RUN mamba install samtools"},
	]
	denyMsgs := data.dockerfile.genomics.deny with input as testInput
	msg := denyMsgs[_]
	startswith(msg, "DGF001")
}

# micromamba install gatk4 (버전 없음) → DGF001
test_dgf001_micromamba_no_version if {
	testInput := [
		{"Cmd": "from", "Raw": "FROM ubuntu:22.04 AS builder"},
		{"Cmd": "run", "Raw": "RUN micromamba install gatk4"},
	]
	denyMsgs := data.dockerfile.genomics.deny with input as testInput
	msg := denyMsgs[_]
	startswith(msg, "DGF001")
}

# conda install bwa=0.7.17=h5bf99c6_8 (버전 고정) → 허용
test_dgf001_conda_with_version_ok if {
	testInput := [
		{"Cmd": "from", "Raw": "FROM ubuntu:22.04 AS builder"},
		{"Cmd": "run", "Raw": "RUN conda install -y bwa=0.7.17=h5bf99c6_8"},
	]
	denyMsgs := data.dockerfile.genomics.deny with input as testInput
	every msg in denyMsgs {
		not startswith(msg, "DGF001")
	}
}

# conda install -f environment.yml (파일 지정) → 허용
test_dgf001_conda_file_ok if {
	testInput := [
		{"Cmd": "from", "Raw": "FROM ubuntu:22.04 AS builder"},
		{"Cmd": "run", "Raw": "RUN conda install -f environment.yml"},
	]
	denyMsgs := data.dockerfile.genomics.deny with input as testInput
	every msg in denyMsgs {
		not startswith(msg, "DGF001")
	}
}

# conda install --file environment.yml (파일 지정) → 허용
test_dgf001_conda_file_long_ok if {
	testInput := [
		{"Cmd": "from", "Raw": "FROM ubuntu:22.04 AS builder"},
		{"Cmd": "run", "Raw": "RUN micromamba install --file environment.yml"},
	]
	denyMsgs := data.dockerfile.genomics.deny with input as testInput
	every msg in denyMsgs {
		not startswith(msg, "DGF001")
	}
}

# ─── DGF002: pip install 버전 고정 강제 ─────────────────────────────────────

# pip install numpy (버전 없음) → DGF002
test_dgf002_pip_no_version if {
	testInput := [
		{"Cmd": "from", "Raw": "FROM ubuntu:22.04 AS builder"},
		{"Cmd": "run", "Raw": "RUN pip install numpy"},
	]
	denyMsgs := data.dockerfile.genomics.deny with input as testInput
	msg := denyMsgs[_]
	startswith(msg, "DGF002")
}

# pip3 install pysam (버전 없음) → DGF002
test_dgf002_pip3_no_version if {
	testInput := [
		{"Cmd": "from", "Raw": "FROM ubuntu:22.04 AS builder"},
		{"Cmd": "run", "Raw": "RUN pip3 install pysam"},
	]
	denyMsgs := data.dockerfile.genomics.deny with input as testInput
	msg := denyMsgs[_]
	startswith(msg, "DGF002")
}

# pip install numpy==1.24.0 (버전 고정) → 허용
test_dgf002_pip_with_version_ok if {
	testInput := [
		{"Cmd": "from", "Raw": "FROM ubuntu:22.04 AS builder"},
		{"Cmd": "run", "Raw": "RUN pip install numpy==1.24.0"},
	]
	denyMsgs := data.dockerfile.genomics.deny with input as testInput
	every msg in denyMsgs {
		not startswith(msg, "DGF002")
	}
}

# pip install -r requirements.txt (requirements 파일) → 허용
test_dgf002_pip_requirements_ok if {
	testInput := [
		{"Cmd": "from", "Raw": "FROM ubuntu:22.04 AS builder"},
		{"Cmd": "run", "Raw": "RUN pip install -r requirements.txt"},
	]
	denyMsgs := data.dockerfile.genomics.deny with input as testInput
	every msg in denyMsgs {
		not startswith(msg, "DGF002")
	}
}

# pip install --requirement requirements.txt → 허용
test_dgf002_pip_requirement_long_ok if {
	testInput := [
		{"Cmd": "from", "Raw": "FROM ubuntu:22.04 AS builder"},
		{"Cmd": "run", "Raw": "RUN pip install --requirement requirements.txt"},
	]
	denyMsgs := data.dockerfile.genomics.deny with input as testInput
	every msg in denyMsgs {
		not startswith(msg, "DGF002")
	}
}

# ─── 정상 케이스 전체 ──────────────────────────────────────────────────────────

# 버전 고정된 conda + pip → deny 없음
test_all_pinned_ok if {
	testInput := [
		{"Cmd": "from", "Raw": "FROM mambaorg/micromamba:1.5.8 AS builder"},
		{"Cmd": "run", "Raw": "RUN micromamba install -y bwa=0.7.17=h5bf99c6_8 samtools=1.18=h50ea8bc_1"},
		{"Cmd": "run", "Raw": "RUN pip install pysam==0.22.0"},
	]
	data.dockerfile.genomics.deny with input as testInput == set()
}
