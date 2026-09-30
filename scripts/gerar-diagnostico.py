#!/usr/bin/env python3
"""Gera supabase/diagnostico-das-migracoes.sql: uma consulta SÓ DE LEITURA que,
colada no SQL Editor do Supabase, diz quais migrações do repositório NÃO estão
(inteiras) no banco de verdade. Nasceu do erro "column e.fotoaguardaremocaoem
does not exist" em produção (30/09/2026).

Como a lista é montada (sem adivinhar lendo o texto das migrações): sobe um
Postgres descartável, aplica as migrações UMA A UMA e, depois de cada uma, tira
a IMPRESSÃO DIGITAL do banco (a consulta IMPRESSAO abaixo): cada tabela, coluna
(tipo, obrigatória, padrão), restrição, índice, regra de acesso (policy),
gatilho, função (o texto exato) e quem pode chamar cada função. Assim se sabe
qual migração deixou cada coisa como ela está no fim.

O diagnóstico tira a mesma impressão do banco de verdade e compara: o que falta
ou está diferente aponta a migração que não foi aplicada, e, quando a versão
que está lá é de uma migração mais velha, diz qual.

Também escreve o MESMO bloco no supabase/conferir-o-banco.sql (a conferência
item a item de todas as migrações) e a lista das migrações publicadas
(supabase/migracoes-publicadas.txt, que só cresce).

Rode sempre que criar uma migração:
  python3 scripts/gerar-diagnostico.py     (precisa de docker; uns 3 minutos)
"""
import glob, hashlib, os, subprocess, sys, time

RAIZ = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..')
SAIDA = os.path.join(RAIZ, 'supabase', 'diagnostico-das-migracoes.sql')
CONFERIDOR = os.path.join(RAIZ, 'supabase', 'conferir-o-banco.sql')
MANIFESTO = os.path.join(RAIZ, 'supabase', 'migracoes-publicadas.txt')
INICIO = '-- >>> impressão de todas as migrações (gerada por scripts/gerar-diagnostico.py; não edite à mão)'
FIM = '-- <<< fim da impressão'
C = 'gamegb-impressao'

# A impressão digital. É a MESMA consulta no banco de montagem e no de verdade.
# Só entra o que as migrações criam: schema public inteiro, e as regras de
# acesso e gatilhos nossos em storage/auth (o resto desses dois é do Supabase).
IMPRESSAO = r"""
SELECT 'tabela'::text AS tipo, c.relname::text AS chave,
       md5(c.relkind::text || c.relrowsecurity::text) AS marca
  FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
 WHERE n.nspname = 'public' AND c.relkind IN ('r', 'v', 'm', 'p')
UNION ALL
SELECT 'coluna', c.relname || '.' || a.attname,
       md5(format_type(a.atttypid, a.atttypmod) || a.attnotnull::text || coalesce(pg_get_expr(d.adbin, d.adrelid), ''))
  FROM pg_attribute a JOIN pg_class c ON c.oid = a.attrelid JOIN pg_namespace n ON n.oid = c.relnamespace
  LEFT JOIN pg_attrdef d ON d.adrelid = a.attrelid AND d.adnum = a.attnum
 WHERE n.nspname = 'public' AND c.relkind IN ('r', 'v', 'm', 'p') AND a.attnum > 0 AND NOT a.attisdropped
UNION ALL
SELECT 'restricao', c.relname || '.' || k.conname, md5(pg_get_constraintdef(k.oid))
  FROM pg_constraint k JOIN pg_class c ON c.oid = k.conrelid JOIN pg_namespace n ON n.oid = c.relnamespace
 WHERE n.nspname = 'public'
UNION ALL
SELECT 'indice', i.indexname::text, md5(i.indexdef)
  FROM pg_indexes i WHERE i.schemaname = 'public'
UNION ALL
SELECT 'policy', p.schemaname || '.' || p.tablename || '.' || p.policyname,
       md5(p.cmd || p.permissive || array_to_string(p.roles, ',') || coalesce(p.qual, '') || '|' || coalesce(p.with_check, ''))
  FROM pg_policies p
 WHERE p.schemaname = 'public'
    OR (p.schemaname = 'storage' AND p.tablename = 'objects')
UNION ALL
SELECT 'gatilho', n.nspname || '.' || c.relname || '.' || t.tgname, md5(pg_get_triggerdef(t.oid) || t.tgenabled::text)
  FROM pg_trigger t JOIN pg_class c ON c.oid = t.tgrelid JOIN pg_namespace n ON n.oid = c.relnamespace
 WHERE NOT t.tgisinternal
   AND (n.nspname = 'public' OR t.tgname LIKE 'stgame%')
UNION ALL
SELECT 'funcao', p.proname || '(' || pg_get_function_identity_arguments(p.oid) || ')',
       md5(p.prosrc || p.prosecdef::text || coalesce(array_to_string(p.proconfig, ','), ''))
  FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
 WHERE n.nspname = 'public'
UNION ALL
SELECT 'acesso', p.proname || '(' || pg_get_function_identity_arguments(p.oid) || ')',
       md5(has_function_privilege('anon', p.oid, 'EXECUTE')::text
           || has_function_privilege('authenticated', p.oid, 'EXECUTE')::text)
  FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
 WHERE n.nspname = 'public'
"""


def sh(*a, entrada=None, ok=True):
    r = subprocess.run(a, input=entrada, capture_output=True, text=True)
    if ok and r.returncode != 0:
        sys.exit(f"falhou: {' '.join(a)}\n{r.stderr}")
    return r


def psql_arquivo(caminho):
    sh('docker', 'cp', caminho, f'{C}:/x.sql')
    return sh('docker', 'exec', C, 'psql', '-U', 'postgres', '-q', '-v', 'ON_ERROR_STOP=1', '-f', '/x.sql', ok=False)


def impressao():
    r = sh('docker', 'exec', '-i', C, 'psql', '-U', 'postgres', '-v', 'ON_ERROR_STOP=1', '-qtAF', '\t', entrada=IMPRESSAO)
    # 12 letras da marca bastam (e o arquivo fica menor para colar no SQL Editor).
    return {tuple(l.split('\t')[:2]): l.split('\t')[2][:12] for l in r.stdout.splitlines() if l}


def montar(pular=(), trocar=None):
    """Aplica as migrações uma a uma e devolve (antes, [(migracao, impressao)]).
    trocar = {migracao: caminho}: usa outro texto para aquela migração."""
    sh('docker', 'rm', '-f', '-v', C, ok=False)
    sh('docker', 'run', '-d', '--name', C, '--tmpfs', '/var/lib/postgresql/data', '-e', 'POSTGRES_PASSWORD=teste', 'postgres:17')
    for _ in range(90):
        time.sleep(1)
        logs = sh('docker', 'logs', C, ok=False)
        if (logs.stdout + logs.stderr).count('ready to accept connections') >= 2 and \
           sh('docker', 'exec', C, 'psql', '-U', 'postgres', '-qtAc', 'select 1', ok=False).returncode == 0:
            break
    psql_arquivo(os.path.join(RAIZ, 'supabase', 'tests', '_ambiente_local.sql'))
    antes = impressao()
    passos = []
    for arq in sorted(glob.glob(os.path.join(RAIZ, 'supabase', 'migrations', '*.sql'))):
        mig = os.path.basename(arq)[:-4]
        if any(mig.startswith(p) for p in pular):
            continue
        r = psql_arquivo((trocar or {}).get(mig, arq))
        if r.returncode != 0:
            sys.exit(f"a migração {mig} falhou no banco de montagem:\n{r.stderr}")
        passos.append((mig, impressao()))
    return antes, passos


def q(x):
    return "'" + x.replace("'", "''") + "'"


def gerar():
    antes, passos = montar()
    final = passos[-1][1]
    # De qual migração é cada coisa como está no fim: a última que a mudou.
    dona, anterior = {}, dict(antes)
    historico = {}  # (tipo, chave, marca) -> migração que a deixou assim (a primeira)
    for mig, imp in passos:
        for k, marca in imp.items():
            if anterior.get(k) != marca:
                dona[k] = mig
                historico.setdefault((k[0], k[1], marca), mig)
        anterior = imp
    if len(final) < 1000:
        sys.exit(f"a impressão digital final tem só {len(final)} itens: algo deu errado")
    fim = sorted((dona[k], k[0], k[1], m) for k, m in final.items() if antes.get(k) != m)
    velhas = sorted((t, c, m, mig) for (t, c, m), mig in historico.items() if final.get((t, c)) != m)
    migracoes = [m for m, _ in passos]

    # Migração editada DEPOIS de publicada (aconteceu três vezes): quem aplicou
    # a primeira versão tem outra coisa no banco. Monta também com cada versão
    # antiga, para o diagnóstico dizer "está a PRIMEIRA versão de ...".
    for mig in migracoes:
        caminho = f'supabase/migrations/{mig}.sql'
        commits = sh('git', '-C', RAIZ, 'log', '--format=%h %ad', '--date=format:%d/%m %H:%M', '--', caminho).stdout.splitlines()
        for linha in commits[1:]:
            commit, quando = linha.split(' ', 1)
            texto = sh('git', '-C', RAIZ, 'show', f'{commit}:{caminho}').stdout
            tmp = f'/tmp/diagnostico-{mig}-{commit}.sql'
            open(tmp, 'w').write(texto)
            try:
                a2, p2 = montar(trocar={mig: tmp})
            finally:
                os.remove(tmp)
            rotulo = f'{mig} (versão de {quando}, trocada depois)'
            for passo, imp in p2:
                if passo < mig:
                    continue
                for (t, c), m in imp.items():
                    if final.get((t, c)) != m and a2.get((t, c)) != m and (t, c, m) not in historico:
                        historico[(t, c, m)] = rotulo
                        velhas.append((t, c, m, rotulo))
    velhas.sort()

    linhas_fim = ',\n'.join(f"  ({q(a)},{q(b)},{q(c)},{q(d)})" for a, b, c, d in fim)
    linhas_velhas = ',\n'.join(f"  ({q(a)},{q(b)},{q(c)},{q(d)})" for a, b, c, d in velhas)
    linhas_migs = ',\n'.join(f"  ({q(m)})" for m in migracoes)
    # O MESMO bloco vai no diagnóstico e no conferidor (CTEs com prefixo imp_,
    # para não trombar com os nomes do conferidor).
    bloco = f"""imp_migracoes(migracao) AS (VALUES
{linhas_migs}
),
imp_esperado(migracao, tipo, chave, marca) AS (VALUES
{linhas_fim}
),
imp_velhas(tipo, chave, marca, migracao) AS (VALUES
{linhas_velhas}
),
imp_aqui AS (SELECT i.tipo, i.chave, left(i.marca, 12) AS marca FROM ({IMPRESSAO}) i),
imp_faltas AS (
  SELECT e.migracao,
         e.tipo || ' ' || e.chave ||
         CASE WHEN a.marca IS NULL THEN ' (não existe)'
              WHEN v.migracao IS NOT NULL THEN ' (está a versão de ' || v.migracao || ')'
              ELSE ' (diferente: não é versão de migração nenhuma)' END AS falta
    FROM imp_esperado e
    LEFT JOIN imp_aqui a ON a.tipo = e.tipo AND a.chave = e.chave
    LEFT JOIN imp_velhas v ON v.tipo = e.tipo AND v.chave = e.chave AND v.marca = a.marca
   WHERE a.marca IS DISTINCT FROM e.marca
)"""
    sql = f"""-- =========================================================================
-- STGame: DIAGNÓSTICO de quais migrações do repositório NÃO estão neste banco.
-- SÓ LEITURA: não muda nada. Gerado por scripts/gerar-diagnostico.py
-- ({len(migracoes)} migrações, até {migracoes[-1]}).
--
-- Como usar: Supabase -> SQL Editor -> New query -> colar TUDO -> Run.
-- Mande para o Claude o resultado inteiro (todas as linhas).
--
-- Cada linha é uma migração com alguma coisa que ela deixa no banco faltando
-- ou diferente: tabela, coluna, restrição, índice, regra de acesso, gatilho,
-- função (o texto exato) ou quem pode chamar a função. Quando o que está no
-- banco é a versão de uma migração MAIS VELHA, a linha diz de qual.
-- A última linha é o resumo.
-- =========================================================================
WITH {bloco},
imp_sobras AS (
  -- O que existe aqui e as migrações não criam (ou apagaram depois).
  SELECT a.tipo || ' ' || a.chave || coalesce(' (apagado/substituído depois da ' || v.migracao || ')', '') AS sobra
    FROM imp_aqui a
    LEFT JOIN imp_velhas v ON v.tipo = a.tipo AND v.chave = a.chave AND v.marca = a.marca
   WHERE NOT EXISTS (SELECT 1 FROM imp_esperado e WHERE e.tipo = a.tipo AND e.chave = a.chave)
     AND a.tipo IN ('tabela', 'coluna', 'funcao', 'policy', 'gatilho')
)
SELECT m.migracao AS "migração", count(*) AS "itens",
       string_agg(f.falta, '; ' ORDER BY f.falta) AS "o que falta ou está diferente"
  FROM imp_migracoes m JOIN imp_faltas f ON f.migracao = m.migracao
 GROUP BY m.migracao
UNION ALL
SELECT 'zz SOBRAS (existem aqui e não vêm das migrações)', count(*), string_agg(sobra, '; ' ORDER BY sobra)
  FROM imp_sobras HAVING count(*) > 0
UNION ALL
SELECT 'zzz RESUMO: ' || (SELECT count(*) FROM imp_migracoes) || ' migrações no repositório; '
       || (SELECT count(DISTINCT migracao) FROM imp_faltas) || ' com alguma coisa faltando ou diferente; '
       || (SELECT count(*) FROM imp_migracoes m WHERE NOT EXISTS (SELECT 1 FROM imp_esperado e WHERE e.migracao = m.migracao))
       || ' sem marca própria (tudo o que criaram foi substituído depois); Postgres '
       || current_setting('server_version'), NULL, NULL
 ORDER BY 1;
"""
    open(SAIDA, 'w').write(sql)

    # O conferidor leva o mesmo bloco, entre as duas marcas.
    conf = open(CONFERIDOR).read()
    a, b = conf.index(INICIO), conf.index(FIM)
    open(CONFERIDOR, 'w').write(conf[:a] + INICIO + '\n' + bloco + ',\n' + conf[b:])

    # Migração publicada não se edita (a causa do erro de 30/09/2026): a lista
    # só CRESCE. Mudar uma linha que já está nela é à mão, de propósito.
    publicadas = {}
    if os.path.exists(MANIFESTO):
        for linha in open(MANIFESTO):
            if linha.strip() and not linha.startswith('#'):
                h, nome = linha.split()
                publicadas[nome] = h
    for mig in migracoes:
        h = hashlib.sha256(open(os.path.join(RAIZ, 'supabase', 'migrations', mig + '.sql'), 'rb').read()).hexdigest()
        if mig in publicadas and publicadas[mig] != h:
            sys.exit(f"A migração {mig} MUDOU depois de entrar na lista das publicadas. "
                     "Migração publicada não se edita: desfaça a mudança e faça uma migração nova.")
        publicadas.setdefault(mig, h)
    with open(MANIFESTO, 'w') as f:
        f.write("# Migrações publicadas e a impressão (sha256) de cada uma. Só cresce:\n"
                "# migração publicada não se edita (30/09/2026). Gerado por scripts/gerar-diagnostico.py;\n"
                "# conferido por src/ui/migracoes-publicadas.test.ts.\n")
        for nome in sorted(publicadas):
            f.write(f"{publicadas[nome]}  {nome}\n")
    print(f"{SAIDA}: {len(migracoes)} migrações, {len(fim)} itens esperados, {len(velhas)} versões antigas conhecidas")


if __name__ == '__main__':
    try:
        gerar()
    finally:
        sh('docker', 'rm', '-f', '-v', C, ok=False)
