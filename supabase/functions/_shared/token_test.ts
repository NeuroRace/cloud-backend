import { assertEquals } from "jsr:@std/assert@1";
import { tokenMatches } from "./token.ts";

Deno.test("token valido casa", async () => {
  assertEquals(await tokenMatches("s3cret-token", "s3cret-token"), true);
});
Deno.test("token invalido rejeitado", async () => {
  assertEquals(await tokenMatches("wrong", "s3cret-token"), false);
});
Deno.test("token nulo rejeitado", async () => {
  assertEquals(await tokenMatches(null, "s3cret-token"), false);
});
Deno.test("esperado vazio nunca casa (secret ausente no ambiente)", async () => {
  assertEquals(await tokenMatches("", ""), false);
});
