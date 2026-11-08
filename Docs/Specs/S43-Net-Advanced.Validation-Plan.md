# S43 Net-Advanced - Plano de validacao

**Branch:** `feature/s43-advanced-networking-ssl-tls`  
**Data:** 2026-07-30  
**Estado:** procedimentos definidos; execucao runtime e carga adiada ate o
fechamento das otimizacoes.

## 1. Regras de aceite

- Executar cada area isoladamente antes do teste integrado.
- Registrar commit, Delphi, OpenSSL, sistema operacional e hardware.
- Executar testes funcionais antes de carga, stress e benchmark.
- Nao comparar throughput sem igualar TLS, keep-alive, payload, concorrencia e
  limites entre Dext, Go e ASP.NET Core.
- Considerar uma area aprovada apenas sem erros funcionais, vazamentos
  crescentes, filas sem limite ou conexoes presas apos o encerramento.

## 2. Matriz de compilacao

Compilar com Delphi 13:

| Projeto | Debug | Release | Plataforma |
|---|---:|---:|---|
| `Tests/Net/Dext.Net.Socket.Tests.dproj` | obrigatorio | obrigatorio | Win64 |
| `Tests/Web/Dext.Web.UnitTests.dproj` | obrigatorio | obrigatorio | Win32 |
| `Tests/Hubs/TestDextHubs.dproj` | obrigatorio | obrigatorio | Win32 |
| `Examples/02-Web/Web.SslDemo/Web.SslDemo.dproj` | obrigatorio | obrigatorio | Win32 |
| `Apps/CLI/DextTool.dproj` | obrigatorio | obrigatorio | Win32 |
| servidor epoll | obrigatorio | obrigatorio | Linux64 via PA-Server |

Aceite: zero erros de compilacao. Warnings novos devem ser classificados antes
da validacao runtime.

Para validar somente o unit Linux do `epoll`, sem iniciar aplicacao, usar o
compilador `dcclinux64` com os diretorios `Sources/Core`, `Sources/Common`,
`Sources/Server`, `Sources/Net`, `Sources/Web`, `Sources/Hosting`,
`Sources/Testing`, `Sources/Data`, `Sources/Events` e `Sources/Hubs` em `-U` e
`-I`, gravando DCUs em `Temp/EpollCompile/Linux64`. A compilacao direta foi
usada nesta etapa; o build completo e o deploy dependem do PA-Server.

## 2.1 Benchmarks S43 adicionados

O projeto `Benchmarks/Dext.Benchmarks.dpr` agora registra benchmarks de hot
path para MessagePack, DEFLATE e encode/decode de frames WebSocket:

- `BM_S43_MessagePack_Serialize`;
- `BM_S43_MessagePack_Roundtrip`;
- `BM_S43_MessagePack_ComplexRoundtrip`;
- `BM_S43_Deflate_Compress`;
- `BM_S43_Deflate_Roundtrip`;
- `BM_S43_WebSocket_EncodeDecode`.

Esses benchmarks medem custo de CPU e alocacao dos codecs isoladamente. Eles
nao substituem os testes end-to-end de HTTPS/WSS, pois nao exercitam socket,
IOCP, epoll, OpenSSL ou clientes externos.

Execucao posterior recomendada:

```text
Dext.Benchmarks.exe --benchmark_filter=BM_S43_
```

Registrar commit, plataforma, configuracao, CPU, memoria, iteracoes,
tempo/op, throughput e tamanho de entrada/saida.

Para carga HTTP reproduzivel, usar `Benchmarks/run_s43_http_load.ps1`. O script
aceita `-Engine indy|httpsys|epoll`, `-Concurrency`, `-DurationSeconds` e
`-Wsl`; coleta CPU e memoria do processo Windows quando aplicavel e encerra o
servidor em `finally`.

Para HTTPS/WSS, usar `Benchmarks/run_s43_tls_smoke.ps1` contra o endpoint ja
levantado. O script verifica HTTP com `curl`, handshake e ALPN basico com
`openssl s_client` e, quando informado, troca dados por WSS com `websocat`.

Resultado em WSL2/PA-Server (30/07/2026), apos a correcao de inicializacao do
writer MessagePack: Ping roundtrip em torno de 465 ns/op, serializacao em
torno de 887 ns/op, Invocation complexo em torno de 5,2 us/op, DEFLATE
compressao em torno de 15,3 us/op, DEFLATE roundtrip em torno de 6,1 us/op e
WebSocket encode/decode em torno de 719 ns/op. A falha Linux foi causada por
`FLength` nao inicializado no record interno do writer e foi corrigida com
inicializacao explicita.

## 3. OpenSSL Memory BIO

### 3.1 Testes unitarios em memoria

1. Criar cliente e servidor com um `SSL_CTX` compartilhado por provider.
2. Transferir todo ciphertext entre os BIOs em blocos de 1, 7, 1.024 e 16.384
   bytes.
3. Completar handshake TLS 1.2 e TLS 1.3.
4. Negociar `h2` e `http/1.1` por ALPN.
5. Fazer roundtrip de payloads de 0 B, 1 B, 16 KiB, 64 KiB e 1 MiB.
6. Forcar partial write e alternancia `WANT_READ`/`WANT_WRITE`.
7. Executar `close_notify` bilateral e encerramento abrupto.

### 3.2 Certificados

- certificado e chave correspondentes;
- chave incorreta;
- certificado expirado;
- CA nao confiavel;
- CA bundle customizado;
- hostname correto, incorreto, SAN DNS e SAN IP;
- arquivo ausente, sem permissao e PEM malformado.

Aceite: falha imediata e diagnostico especifico para toda configuracao invalida.

## 4. Redis TLS

1. Subir Redis/Memurai com TLS e certificado de teste.
2. Validar `PING`, `SET`/`GET`, payload grande e pipeline de comandos.
3. Fragmentar artificialmente entrada e saida TLS.
4. Repetir reconexao, erro de certificado e shutdown remoto.
5. Saturar o pool com clientes concorrentes e cliente lento.

Medir alocacoes por comando, bytes pendentes, latencia p50/p95/p99 e crescimento
de memoria durante pelo menos 30 minutos.

## 5. http.sys HTTPS

### 5.1 Provisionamento

Exemplos:

```powershell
dext dev-certs https --trust --bind --ip 0.0.0.0 --port 8080 `
  --store MY --appid "{4f3b2c10-8a9b-4d7e-8f12-3456789abcde}"

dext dev-certs https --trust --update-binding --ip 0.0.0.0 --port 8080 `
  --store MY --appid "{4f3b2c10-8a9b-4d7e-8f12-3456789abcde}"

netsh http show sslcert ipport=0.0.0.0:8080
```

### 5.2 Startup

- binding ausente;
- thumbprint divergente;
- store divergente;
- AppId divergente;
- binding totalmente correspondente.

Aceite: os quatro primeiros falham antes de escutar; o ultimo inicia HTTPS.

## 6. WebSocket sobre http.sys

### 6.1 Protocolo

- handshake RFC 6455;
- frame cliente sem mask;
- RSV/opcode invalido;
- comprimento nao canonico e acima do limite;
- ping/pong e close;
- texto UTF-8 valido e invalido;
- fragmentacao texto e continuation;
- frames concatenados e frame dividido em varias leituras.

### 6.2 IOCP e backpressure

1. Confirmar que conexao ociosa nao ocupa worker.
2. Forcar completions parciais de receive/send.
3. Suspender leitura de um cliente ate exceder a fila.
4. Confirmar fechamento apenas do cliente lento e remocao no Hub.
5. Encerrar servidor com receives e sends pendentes.
6. Verificar que callbacks nao mantem conexoes vivas.

Executar com 1 mil, 10 mil e, se o ambiente suportar, 50 mil conexoes. Medir
RSS por conexao, handles, threads, context switches, fila maxima e desconexoes.

## 7. MessagePack

- comparar bytes produzidos com ASP.NET Core SignalR;
- testar todos os tipos de mensagem Hub;
- validar prefixo VarInt e mensagens concatenadas/parciais;
- testar nil, boolean, inteiros, floats, UTF-8, binario, arrays e mapas;
- comparar tamanho, CPU e alocacoes com JSON.

## 8. Permessage-deflate

- negociacao aceita, recusada e parametros invalidos;
- RSV1 somente no primeiro frame de mensagem comprimida;
- payload fragmentado;
- context takeover ligado/desligado;
- limite de saida descomprimida e zip bomb;
- texto e binario incompressivel;
- close/ping/pong nunca comprimidos.

Medir bytes economizados, CPU e latencia por faixas de payload antes de definir
o limiar adaptativo de compressao.

## 9. epoll HTTPS/WSS no Linux

Esta etapa depende do ambiente Delphi Linux64 integrado por PA-Server e foi
deliberadamente reservada para o final.

1. Preparar Linux/WSL2, PA-Server, OpenSSL suportado e certificados.
2. Compilar e executar o servidor Linux64.
3. Validar HTTPS 1.1, ALPN `h2`, WSS e shutdown TLS.
4. Forcar `WANT_READ` durante escrita e `WANT_WRITE` durante leitura.
5. Testar partial socket send, cliente lento e encerramento abrupto.
6. Executar stress prolongado e verificar descritores, RSS e vazamentos.

## 10. Benchmark competitivo

Comparar Release sem debugger:

- Dext `http.sys` versus ASP.NET Core HTTP.sys no Windows;
- Dext epoll/OpenSSL versus ASP.NET Core Kestrel e Go `net/http` no Linux;
- HTTPS keep-alive com resposta vazia, JSON de 1 KiB e 64 KiB;
- WSS echo de 32 B, 1 KiB e 64 KiB;
- broadcast para 1 mil, 10 mil e 50 mil conexoes;
- JSON versus MessagePack;
- compressao ligada/desligada;
- handshake com e sem session resumption.

Coletar throughput, p50/p95/p99/p99.9, CPU total e por core, RSS, alocacoes,
context switches, syscalls, bytes transmitidos e taxa de erro. Executar
aquecimento, no minimo cinco amostras e publicar mediana e dispersao.
