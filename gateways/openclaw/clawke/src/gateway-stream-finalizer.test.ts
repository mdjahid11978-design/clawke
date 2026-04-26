import test from "node:test";
import assert from "node:assert/strict";
import { GatewayBoundaryFinalizer } from "./gateway-stream-finalizer.ts";

test("GatewayBoundaryFinalizer consumes duplicate final text after boundary finalization", () => {
  const finalizer = new GatewayBoundaryFinalizer();

  finalizer.recordBoundaryFinalized("好问题，让我查一下 skill 的状态:");

  assert.equal(
    finalizer.consumeDuplicateFinal("好问题，让我查一下 skill 的状态:"),
    true,
  );
  assert.equal(
    finalizer.consumeDuplicateFinal("好问题，让我查一下 skill 的状态:"),
    false,
  );
});

test("GatewayBoundaryFinalizer does not suppress different final text", () => {
  const finalizer = new GatewayBoundaryFinalizer();

  finalizer.recordBoundaryFinalized("先查一下状态");

  assert.equal(finalizer.consumeDuplicateFinal("状态正常"), false);
});
