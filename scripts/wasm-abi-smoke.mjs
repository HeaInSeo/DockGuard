// OPA WASM ABI / entrypoint smoke for the NodeKit consumer contract.
//
// NodeKit (WasmPolicyChecker) instantiates dockguard.wasm with the standard OPA
// env imports and evaluates entrypoint index 0 via opa_eval_ctx_set_entrypoint.
// This checks that the built module exposes that ABI and that the entrypoint
// ids map to the expected ordered list.
//
// usage: node scripts/wasm-abi-smoke.mjs build/dockguard.wasm dockerfile/multistage/deny [...]
import { readFileSync } from "node:fs";

const [wasmPath, ...expected] = process.argv.slice(2);
if (!wasmPath || expected.length === 0) {
  console.error("usage: wasm-abi-smoke.mjs <wasm> <entrypoint>...");
  process.exit(2);
}

const memory = new WebAssembly.Memory({ initial: 5 });
const fail = (name) => () => {
  throw new Error(`unexpected host call: ${name}`);
};
const env = {
  memory,
  opa_abort: fail("opa_abort"),
  opa_println: () => {},
  opa_builtin0: fail("opa_builtin0"),
  opa_builtin1: fail("opa_builtin1"),
  opa_builtin2: fail("opa_builtin2"),
  opa_builtin3: fail("opa_builtin3"),
  opa_builtin4: fail("opa_builtin4"),
};

const { instance } = await WebAssembly.instantiate(readFileSync(wasmPath), { env });
const ex = instance.exports;

const required = [
  "opa_eval_ctx_new",
  "opa_eval_ctx_set_input",
  "opa_eval_ctx_set_data",
  "opa_eval_ctx_set_entrypoint",
  "opa_eval_ctx_get_result",
  "opa_json_dump",
  "opa_json_parse",
  "opa_malloc",
  "opa_heap_ptr_get",
  "opa_heap_ptr_set",
  "eval",
  "builtins",
  "entrypoints",
];
const missing = required.filter((name) => !(name in ex));
if (missing.length > 0) {
  console.error(`missing OPA ABI exports: ${missing.join(", ")}`);
  process.exit(1);
}

const abiMajor = ex.opa_wasm_abi_version?.value;
const abiMinor = ex.opa_wasm_abi_minor_version?.value;
console.log(`opa_wasm_abi_version=${abiMajor} minor=${abiMinor}`);
if (abiMajor !== 1) {
  console.error(`unsupported OPA wasm ABI major version: ${abiMajor}`);
  process.exit(1);
}

const readCString = (addr) => {
  const bytes = new Uint8Array(memory.buffer, addr);
  let end = 0;
  while (bytes[end] !== 0) end++;
  return new TextDecoder().decode(bytes.subarray(0, end));
};

// entrypoints() returns {"<entrypoint>": <id>, ...}; id is the value passed to
// opa_eval_ctx_set_entrypoint.
const entrypoints = JSON.parse(readCString(ex.opa_json_dump(ex.entrypoints())));
console.log(`entrypoints=${JSON.stringify(entrypoints)}`);

const byId = Object.entries(entrypoints).sort((a, b) => a[1] - b[1]).map(([name]) => name);
if (JSON.stringify(byId) !== JSON.stringify(expected)) {
  console.error(`entrypoint order mismatch: got ${JSON.stringify(byId)}, want ${JSON.stringify(expected)}`);
  process.exit(1);
}

// Host-provided builtins are recorded, not judged: whether the NodeKit host
// implements them is the consumer's (S3) acceptance, not this producer check.
const builtins = JSON.parse(readCString(ex.opa_json_dump(ex.builtins())));
console.log(`host_builtins=${JSON.stringify(builtins)}`);

console.log(`ABI smoke OK: index 0 = ${expected[0]}`);
