import { assertEquals } from "jsr:@std/assert@1";
import { tokenMatches } from "./auth.ts";

Deno.test("token valido casa", async () => {
  assertEquals(await tokenMatches("s3cret-token", "s3cret-token"), true);
});
Deno.test("token invalido rejeitado", async () => {
  assertEquals(await tokenMatches("wrong", "s3cret-token"), false);
});
Deno.test("token nulo rejeitado", async () => {
  assertEquals(await tokenMatches(null, "s3cret-token"), false);
});
Deno.test("tamanho diferente rejeitado", async () => {
  assertEquals(await tokenMatches("s3cret-token-longo", "s3cret-token"), false);
});
