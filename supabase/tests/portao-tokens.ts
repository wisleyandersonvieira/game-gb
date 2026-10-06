// Chaves e tokens do teste do PORTÃO (supabase/tests/portao.sh, 06/10/2026).
// As chaves nascem numa pasta temporária a cada rodada e são apagadas no fim:
// nenhuma chave de verdade passa por aqui.
// uso: bun portao-tokens.ts chave <dir> <nome>  |  bun portao-tokens.ts token <dir> <nome> <tipo> [sub]
const [modo, dir, nome, tipo, sub] = process.argv.slice(2);
const b64u = (b: ArrayBuffer | Uint8Array) =>
  Buffer.from(b instanceof Uint8Array ? b : new Uint8Array(b)).toString("base64url");
if (modo === "chave") {
  const par = await crypto.subtle.generateKey({ name: "ECDSA", namedCurve: "P-256" }, true, ["sign", "verify"]);
  const kid = crypto.randomUUID();
  const priv = { ...(await crypto.subtle.exportKey("jwk", par.privateKey)), kid, alg: "ES256", use: "sig" };
  const pub = { ...(await crypto.subtle.exportKey("jwk", par.publicKey)), kid, alg: "ES256", use: "sig" };
  await Bun.write(`${dir}/${nome}.privada.json`, JSON.stringify(priv));
  await Bun.write(`${dir}/${nome}.publica.json`, JSON.stringify(pub));
  console.log(kid);
} else if (modo === "token") {
  const priv = JSON.parse(await Bun.file(`${dir}/${nome}.privada.json`).text());
  const chave = await crypto.subtle.importKey("jwk", priv, { name: "ECDSA", namedCurve: "P-256" }, false, ["sign"]);
  const agora = Math.floor(Date.now() / 1000);
  const base = { iat: agora, aud: "authenticated", iss: "stgame-portao" };
  const formatos: Record<string, object> = {
    A: { ...base, role: "authenticated", sub, exp: agora + 300, canal: "whatsapp" },
    B: { ...base, role: "wa_porteiro", exp: agora + 60, canal: "whatsapp_porteiro" },
    servidor: { ...base, role: "service_role", exp: agora + 300 },
    servidor_com_marca: { ...base, role: "service_role", exp: agora + 300, canal: "whatsapp" },
    A_longo: { ...base, role: "authenticated", sub, exp: agora + 3600, canal: "whatsapp" },
    sem_marca: { ...base, role: "authenticated", sub, exp: agora + 300 },
    comum: { ...base, role: "authenticated", sub, exp: agora + 300 },
  };
  const corpo = formatos[tipo];
  if (!corpo) throw new Error("tipo desconhecido: " + tipo);
  const cab = { alg: "ES256", typ: "JWT", kid: priv.kid };
  const entrada = `${b64u(new TextEncoder().encode(JSON.stringify(cab)))}.${b64u(new TextEncoder().encode(JSON.stringify(corpo)))}`;
  const assin = await crypto.subtle.sign({ name: "ECDSA", hash: "SHA-256" }, chave, new TextEncoder().encode(entrada));
  console.log(`${entrada}.${b64u(assin)}`);
}
