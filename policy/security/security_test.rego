# policy/security/security_test.rego
package dockerfile.security

# ─── DSF001 ──────────────────────────────────────────────────────────────────

# USER 없음 → DSF001
test_dsf001_no_user if {
	testInput := [
		{"Cmd": "from", "Raw": "FROM ubuntu:22.04 AS builder"},
		{"Cmd": "run", "Raw": "RUN apt-get update -y"},
	]
	denyMsgs := data.dockerfile.security.deny with input as testInput
	msg := denyMsgs[_]
	startswith(msg, "DSF001")
}

# USER root → DSF001
test_dsf001_user_root if {
	testInput := [
		{"Cmd": "from", "Raw": "FROM ubuntu:22.04 AS builder"},
		{"Cmd": "user", "Raw": "USER root"},
	]
	denyMsgs := data.dockerfile.security.deny with input as testInput
	msg := denyMsgs[_]
	startswith(msg, "DSF001")
}

# USER 0 → DSF001
test_dsf001_user_zero if {
	testInput := [
		{"Cmd": "from", "Raw": "FROM ubuntu:22.04 AS builder"},
		{"Cmd": "user", "Raw": "USER 0"},
	]
	denyMsgs := data.dockerfile.security.deny with input as testInput
	msg := denyMsgs[_]
	startswith(msg, "DSF001")
}

# USER nonroot → 허용 (DSF001 없음)
test_dsf001_user_nonroot_ok if {
	testInput := [
		{"Cmd": "from", "Raw": "FROM ubuntu:22.04 AS builder"},
		{"Cmd": "user", "Raw": "USER nonroot"},
	]
	denyMsgs := data.dockerfile.security.deny with input as testInput

	# DSF001이 없어야 함
	every msg in denyMsgs {
		not startswith(msg, "DSF001")
	}
}

# USER 1000 (UID) → 허용 (DSF001 없음)
test_dsf001_user_uid_ok if {
	testInput := [
		{"Cmd": "from", "Raw": "FROM ubuntu:22.04 AS builder"},
		{"Cmd": "user", "Raw": "USER 1000"},
	]
	denyMsgs := data.dockerfile.security.deny with input as testInput
	every msg in denyMsgs {
		not startswith(msg, "DSF001")
	}
}

# ─── DSF002 ──────────────────────────────────────────────────────────────────

# ENV PASSWORD=secret → DSF002
test_dsf002_env_password if {
	testInput := [
		{"Cmd": "from", "Raw": "FROM ubuntu:22.04 AS builder"},
		{"Cmd": "user", "Raw": "USER 1000"},
		{"Cmd": "env", "Raw": "ENV PASSWORD=super_secret", "Value": ["PASSWORD=super_secret"]},
	]
	denyMsgs := data.dockerfile.security.deny with input as testInput
	msg := denyMsgs[_]
	startswith(msg, "DSF002")
}

# ENV API_KEY=xxx → DSF002
test_dsf002_env_api_key if {
	testInput := [
		{"Cmd": "from", "Raw": "FROM ubuntu:22.04 AS builder"},
		{"Cmd": "user", "Raw": "USER 1000"},
		{"Cmd": "env", "Raw": "ENV API_KEY=abc123", "Value": ["API_KEY=abc123"]},
	]
	denyMsgs := data.dockerfile.security.deny with input as testInput
	msg := denyMsgs[_]
	startswith(msg, "DSF002")
}

# ENV CONDA_PATH=/opt/conda → 허용 (DSF002 없음)
test_dsf002_env_conda_path_ok if {
	testInput := [
		{"Cmd": "from", "Raw": "FROM ubuntu:22.04 AS builder"},
		{"Cmd": "user", "Raw": "USER 1000"},
		{"Cmd": "env", "Raw": "ENV CONDA_PATH=/opt/conda", "Value": ["CONDA_PATH=/opt/conda"]},
	]
	denyMsgs := data.dockerfile.security.deny with input as testInput
	every msg in denyMsgs {
		not startswith(msg, "DSF002")
	}
}

# ─── DSF003 ──────────────────────────────────────────────────────────────────

# ADD https://... → DSF003
test_dsf003_add_remote_url if {
	testInput := [
		{"Cmd": "from", "Raw": "FROM ubuntu:22.04 AS builder"},
		{"Cmd": "user", "Raw": "USER 1000"},
		{"Cmd": "add", "Raw": "ADD https://example.com/file.tar.gz /opt/", "Value": ["https://example.com/file.tar.gz", "/opt/"]},
	]
	denyMsgs := data.dockerfile.security.deny with input as testInput
	msg := denyMsgs[_]
	startswith(msg, "DSF003")
}

# ADD http://... → DSF003
test_dsf003_add_http_url if {
	testInput := [
		{"Cmd": "from", "Raw": "FROM ubuntu:22.04 AS builder"},
		{"Cmd": "user", "Raw": "USER 1000"},
		{"Cmd": "add", "Raw": "ADD http://example.com/file.tar.gz /opt/", "Value": ["http://example.com/file.tar.gz", "/opt/"]},
	]
	denyMsgs := data.dockerfile.security.deny with input as testInput
	msg := denyMsgs[_]
	startswith(msg, "DSF003")
}

# ADD local/file → 허용 (DSF003 없음)
test_dsf003_add_local_file_ok if {
	testInput := [
		{"Cmd": "from", "Raw": "FROM ubuntu:22.04 AS builder"},
		{"Cmd": "user", "Raw": "USER 1000"},
		{"Cmd": "add", "Raw": "ADD ./scripts /opt/scripts", "Value": ["./scripts", "/opt/scripts"]},
	]
	denyMsgs := data.dockerfile.security.deny with input as testInput
	every msg in denyMsgs {
		not startswith(msg, "DSF003")
	}
}

# ─── 정상 케이스 전체 ──────────────────────────────────────────────────────────

# USER 비루트 + 일반 ENV + 로컬 ADD → deny 없음
test_all_ok if {
	testInput := [
		{"Cmd": "from", "Raw": "FROM ubuntu:22.04 AS builder"},
		{"Cmd": "env", "Raw": "ENV CONDA_PATH=/opt/conda", "Value": ["CONDA_PATH=/opt/conda"]},
		{"Cmd": "run", "Raw": "RUN apt-get update -y"},
		{"Cmd": "user", "Raw": "USER 1000"},
	]
	data.dockerfile.security.deny with input as testInput == set()
}
