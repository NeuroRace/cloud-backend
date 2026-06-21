async function sha256(s: string): Promise<Uint8Array> {
  const digest = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(s));
  return new Uint8Array(digest);
}

/** Compara tokens em tempo constante via digests SHA-256 (tamanho fixo, sem leak de length). */
export async function tokenMatches(provided: string | null, expected: string): Promise<boolean> {
  if (provided === null || expected === "") return false;
  const a = await sha256(provided);
  const b = await sha256(expected);
  let diff = 0;
  for (let i = 0; i < a.length; i++) diff |= a[i] ^ b[i];
  return diff === 0;
}
