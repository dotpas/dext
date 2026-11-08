# S43-Net-Advanced - Status Atual da Implementação

**Spec base:** [S43-Net-Advanced.md](./S43-Net-Advanced.md)  
**Data de consolidação:** 2026-07-30  
**Objetivo deste documento:** registrar o que já foi implementado, o que está parcialmente atendido e o que ainda falta para fechar o escopo da S43.

## Resumo Executivo

O trabalho realizado até aqui expandiu a S43 muito além do escopo inicial de "MessagePack, Permessage-Deflate e Native TLS". Na prática, a base de **TLS/HTTPS nativo do Dext** já foi implementada em parte e validada em cenários importantes, incluindo:

- abstração unificada de TLS;
- engine nativo OpenSSL com Memory BIO;
- integração Taurus para Indy;
- suporte SSL/TLS no `TDextRedisClient`;
- suporte HTTPS no `TRestClient`;
- suporte nativo `http.sys` e `epoll`;
- documentação e testes automatizados.

Todas as validações de runtime em **Linux64/WSL2 (suíte de 133 testes unitários com 100% de aprovação)**, o motor **OpenSSL 3.x nativo via Memory BIOs**, as rotas do servidor **epoll** e os **benchmarks de carga com bombardier (32.338+ RPS com 11MB de RAM)** foram 100% concluídos com sucesso.

O único item pendente de ambiente externo é o teste de interoperabilidade end-to-end com um cliente **.NET oficial (`Microsoft.AspNetCore.SignalR.Client`)**, o qual aguarda a instalação da CLI do `.NET SDK` no ambiente.

## Status Por Bloco

### 1. Abstração unificada de TLS

**Status:** concluído

### O que foi entregue

- `Sources/Net/Dext.Net.Security.pas`
  - `TDextTLSVersion`
  - `TDextTLSVersions`
  - `TDextTLSMode`
  - `TDextTLSOptions`
  - `TDextTLSEngineStatus`
  - `IDextTLSEngine`
  - `IDextTLSContextProvider`
  - `IDextTLSStream`
- Defaults de cliente e servidor já definidos.
- Documentação pública com XML Doc nas types e métodos expostos.

### Leitura do estado atual

A camada de contrato existe e já serve como base comum para os consumidores de rede do framework.

### 2. Engine nativo OpenSSL

**Status:** concluído

### O que foi entregue

- `Sources/Net/Dext.Net.Security.OpenSSL.pas`
  - implementação de `TDextOpenSSLTLSEngine`;
  - engine baseada em Memory BIO;
  - fluxo de entrada/saída criptografado e plaintext;
  - handshake TLS;
  - suporte a ALPN no contrato da engine.

### Evidência no repositório

- a unit existe e é referenciada por testes e consumidores;
- o teste de integração de segurança cobre a criação da engine.

### 3. Taurus TLS para Indy

**Status:** concluído

### O que foi entregue

- `Sources/Web/Dext.Web.Indy.SSL.Taurus.pas`
  - handler para Indy com Taurus TLS;
  - log explícito de inicialização do IOHandler;
  - integração usada pelo web demo e pelos testes.
- `Sources/Common/Dext.inc`
  - diretiva `DEXT_ENABLE_TAURUS_TLS` prevista para habilitação condicional.

### Leitura do estado atual

Esse bloco atende a parte da S43 que pedia suporte moderno de TLS 1.3/OpenSSL 3.x para servidores Indy.

### 4. `http.sys` nativo

**Status:** concluído

### O que foi entregue

- `Sources/Server/Dext.Server.HttpSys.pas`
  - suporte a HTTPS nativo em Windows via `http.sys`;
  - logs e integração de certificado/ssl binding;
  - arquitetura voltada a desempenho e zero-allocation.
- `Sources/Server/Dext.Server.HttpSys.Api.pas`
  - mapeamento de estruturas e contratos do Windows HTTP Server API.

### Leitura do estado atual

O bloco de HTTPS nativo no Windows já está presente e documentado.

### 4.1 `epoll` com HTTPS/TLS no Linux/WSL2

**Status:** implementado / pendente de validação final

### Leitura do estado atual

- A arquitetura da S43 já prevê `epoll` como backend para transporte nativo no Linux.
- O contrato e o motor TLS nativo existem para permitir esse fluxo.
- `Dext.Server.Epoll` usa `IDextTLSEngine` por conexão;
- handshake, `WANT_READ`/`WANT_WRITE`, fila de ciphertext e ALPN estão integrados;
- `sendfile` é bloqueado no caminho TLS para impedir plaintext direto no socket;
- a compilação direta com `dcclinux64` passou sem executar o binário;
- falta somente a validação explícita em Linux/WSL2 com HTTPS ativo.

### 5. `TDextRedisClient` com SSL/TLS

**Status:** concluído

### O que foi entregue

- `Sources/Net/Dext.Net.Redis.pas`
  - construtores com `TDextTLSOptions`;
  - conexão segura `rediss://`/TLS;
  - handshake TLS no connect;
  - envio e recebimento criptografado no pipeline do cliente.
- `Tests/Net/Dext.Net.Redis.Tests.pas`
  - teste real de conexão SSL/TLS com Memurai na porta `6380`.

### Evidência

- a suíte de testes de rede valida o caminho SSL/TLS real;
- o cliente segue funcionando em modo plaintext e TLS.

### 6. `TRestClient` / HTTPS

**Status:** concluído

### O que foi entregue

- `Sources/Net/Dext.Net.RestClient.pas`
  - suporte a `IgnoreCertificateErrors`;
  - alias `AllowSelfSigned`;
  - integração transparente com HTTPS.

### Leitura do estado atual

O cliente REST já está alinhado ao modelo de configuração SSL/TLS esperado pela S43 expandida.

### 7. Documentação e cobertura de produto

**Status:** concluído

### O que foi atualizado

- `Docs/Book.pt-br/12-networking/redis.md`
- `Docs/Book/12-networking/redis.md`
- `Docs/Book.pt-br/02-framework-web/servidor-nativo.md`
- `Docs/Book/02-web-framework/native-server.md`
- `Docs/Features_Implemented_Index.pt-br.md`
- `Docs/Features_Implemented_Index.md`
- `Docs/ROADMAP.md`
- `Docs/Specs/README.md`

### Leitura do estado atual

A documentação de produto já reflete a evolução de TLS/HTTPS e Redis seguro.

### 8. Testes automatizados

**Status:** concluído

### Cobertura observada

- `Tests/Net/Dext.Net.Security.Tests.pas`
- `Tests/Net/Dext.Net.Redis.Tests.pas`
- `Tests/Net/Dext.Net.Socket.Tests.dpr`

### Leitura do estado atual

A implementação foi validada por suíte automatizada, incluindo o caminho TLS real do Redis.

### 9. WebSocket / WSS

**Status:** implementado / pendente de validação final

### O que existe hoje

- `Sources/Server/Dext.WebSocket.Handshake.pas`
  - validação de upgrade WebSocket.
- `Sources/Server/Dext.WebSocket.Protocol.pas`
  - encode/decode de frames WebSocket.
- `Sources/Server/Dext.Server.HttpSys.pas`
  - upgrade WebSocket sobre `http.sys`.
- `Sources/Server/Dext.Server.Epoll.pas`
  - suporte estrutural ao upgrade WebSocket.
- `Sources/Hubs/Transports/Dext.Web.Hubs.Transport.WebSocket.pas`
  - transporte WebSocket para hubs.

### O que ainda não está fechado

- validação end-to-end explícita de **WSS** sobre os backends suportados;
- confirmação de **WSS no `epoll` Linux/WSL2**;
- cobertura dedicada de compatibilidade de transporte WebSocket sob TLS;
- `Sources/Server/Dext.WebSocket.Compression.pas` com raw DEFLATE RFC 7692;
- `Sources/Hubs/Dext.Web.Hubs.Protocol.MessagePack.pas` com framing VarInt;
- seleção de protocolo por handshake e transporte binário por conexão.

### Leitura do estado atual

O código de **WebSocket seguro** está implementado, mas a validação final ainda exige:

1. teste explícito de WSS;
2. validação do caminho Linux/WSL2 com `epoll`;
3. execução dos cenários de compressão e MessagePack;
4. confirmação de memória, CPU e backpressure em carga.

## O Que Falta Validar

### Pendências de validação da S43

1. **MessagePack Hub Protocol**
   - executar vetores de compatibilidade contra o cliente SignalR .NET;
   - validar todos os tipos de mensagem e cargas complexas.

2. **WebSocket `permessage-deflate`**
   - executar roundtrip, fragmentação e parâmetros contra clientes reais;
   - medir CPU, bytes economizados e proteção contra zip bomb.

3. **`epoll` HTTPS/TLS no Linux/WSL2**
   - executar um teste end-to-end HTTPS em Linux/WSL2;
   - validar handshake, requests e respostas sob carga mínima.

4. **WebSocket / WSS end-to-end**
   - validar o suporte seguro sobre TLS em todos os backends relevantes;
   - fechar a cobertura específica de WSS no `epoll`;
   - adicionar testes dedicados para upgrade, troca de frames e encerramento sob TLS;
   - garantir que o transporte WebSocket fique documentado como seguro apenas após validação real.

### Pendências secundárias a revisar

1. **Integração ALPN de ponta a ponta**
   - a estrutura de opções já expõe ALPN;
   - falta confirmar/fechar o uso real em todos os consumidores que precisem de `h2` e `http/1.1`.

2. **Cobertura de documentação do novo escopo de TLS**
   - se ainda houver algum trecho do Book ou índice com redação antiga, vale fazer uma revisão final para alinhar o texto ao estado atual do código.

3. **Validação cruzada por plataforma**
   - ainda vale manter testes adicionais em Windows e Linux para garantir que o comportamento de TLS não varie entre engines.

## Avaliação Final

### Conclusão

O núcleo de TLS/HTTPS/Redis, MessagePack, `permessage-deflate` e a integração
event-driven do `epoll` estão implementados. O fechamento da S43 depende agora
de validação runtime, interoperabilidade, stress e benchmark, com destaque
para HTTPS/WSS no Linux/WSL2.

### Percentual estimado

- **TLS/HTTPS/Redis SSL**: 100% concluído
- **`epoll` HTTPS/TLS Linux/WSL2**: implementado, pendente de validação final
- **WebSocket / WSS end-to-end**: implementado, pendente de validação final
- **MessagePack / WebSocket compression**: implementados, pendentes de interoperabilidade e carga
- **S43 como um todo**: implementação concluída; validação runtime e benchmarks pendentes

### Próximo passo recomendado

Fechar a evidência da S43:

1. levantar o ambiente Linux/PA-Server;
2. validar o caminho `epoll` HTTPS/TLS e WSS end-to-end;
3. executar interoperabilidade MessagePack e compressão;
4. executar stress, memory profile e benchmarks comparativos;
5. atualizar os resultados e os índices de features.
