# 📄 Spec S61: Real-Time Sockets, WebSocket Engine & Zero-Downtime TLS Enhancements

## 🎯 Objetivo Arquitetural
Reforçar o ecossistema Web/Server e de tempo real do **Dext Framework**, consolidando o nosso servidor HTTP/HTTPS e de **WebSockets nativos com Hubs (SignalR Protocol)** frente ao lançamento recente do *TMS Sparkle Socket Server*.

Esta especificação documenta o estado **real** da implementação existente no Dext e detalha o plano de evolução para recursos avançados de infraestrutura de borda (Edge Protection, TLS Hot-Reload e SNI Dinâmico).

---

## 🏛️ 1. Mapeamento das Units Existentes no Dext

O Dext já possui uma arquitetura de WebSockets e Real-time Streaming madura e funcional. As unidades no repositório são:

| Módulo | Caminho da Unit / Teste | Descrição / Responsabilidade |
| :--- | :--- | :--- |
| **Protocol Engine** | [Dext.WebSocket.Protocol.pas](../../Sources/Server/Dext.WebSocket.Protocol.pas) | Framing RFC 6455, Opcodes (`wsText`, `wsBinary`, `wsPing`, `wsPong`, `wsClose`), Masking e Unmasking com vetorização. |
| **Handshake** | [Dext.WebSocket.Handshake.pas](../../Sources/Server/Dext.WebSocket.Handshake.pas) | Validação de upgrade HTTP `101 Switching Protocols`, cálculo SHA-1/Base64 de `Sec-WebSocket-Accept`. |
| **Compressão** | [Dext.WebSocket.Compression.pas](../../Sources/Server/Dext.WebSocket.Compression.pas) | Negociação e compressão RFC 7692 `permessage-deflate` via ZLib (até 80% economia de banda). |
| **Hub Transport** | [Dext.Web.Hubs.Transport.WebSocket.pas](../../Sources/Hubs/Transports/Dext.Web.Hubs.Transport.WebSocket.pas) | Transporte de alta camada para o ecossistema Dext Hubs (compatível com SignalR Protocol). |
| **Testes Unitários** | [Dext.WebSocket.Tests.pas](../../Tests/Web/Dext.WebSocket.Tests.pas) | Cobertura rigorosa de testes unitários para handshake, frames, payload de 64-bit e compressão. |

---

## ⚔️ 2. Comparativo de Arquitetura: Dext vs. TMS Sparkle Socket Server

| Funcionalidade / Recurso | TMS Sparkle Socket Server | Dext Framework | Status Dext |
| :--- | :--- | :--- | :--- |
| **Linux Standalone (No Apache)** | ✅ Sockets nativos (`epoll`) | ✅ Sockets nativos (`epoll` / DCS / Sockets) | **Empate Nível Core** |
| **Windows Driverless (No Http.sys)** | ✅ Sockets nativos (`WSAPoll`) | ✅ Sockets nativos (`WSAPoll` / Sockets) | **Empate Nível Core** |
| **Low-Level WebSocket (RFC 6455)** | ✅ `THttpServerModule` + `IWebSocket` | ✅ `TWebSocketProtocol` + `TWebSocketHandshake` | **Empate Nível Core** |
| **Real-Time Hubs (SignalR Compatible)**| ❌ Não possui (requer código manual) | ✅ **`Dext.Web.Hubs.*` (`IHubClients`, `Groups`, `Caller`)** | 🚀 **Dext é Superior** |
| **Compressão Permessage-Deflate (RFC 7692)** | ❌ Não documentado / Ausente | ✅ **`Dext.WebSocket.Compression.pas`** | 🚀 **Dext é Superior** |
| **Client JS Integrado** | ❌ Não | ✅ **`dext-hubs.js` com auto-reconnect & fallback** | 🚀 **Dext é Superior** |
| **Zero-Downtime TLS Cert Reload** | ✅ `Server.ReloadCertificates` | 🟡 *Em planejamento nesta Spec* | 💡 **Evolução da Spec S61** |
| **Multi-Domain SNI (Server Name Indication)**| ✅ `SniCertificates` Wildcard | 🟡 *Em planejamento nesta Spec* | 💡 **Evolução da Spec S61** |
| **Slowloris Header Shield no EventLoop** | ✅ Assíncrono antes do Worker Thread | 🟡 *Em planejamento nesta Spec* | 💡 **Evolução da Spec S61** |

---

## 🔧 3. Plano de Melhorias da Spec S61 (Novos Recursos para o Dext)

Para superar completamente os novos diferenciais do TMS Sparkle, adicionaremos os seguintes recursos à nossa engine de Socket Server:

### **3.1 TLS Zero-Downtime Hot-Reload (`ReloadCertificates`)**
- **Unit**: `Dext.Net.Security.Certificates.pas` / `Dext.Web.Server.pas`
- **Comportamento**: Método `Server.ReloadCertificates` que relê de forma atômica os arquivos `.pem` / `.key` (ex: atualizados via Certbot / Let's Encrypt).
- Novas conexões TLS utilizarão os novos certificados imediatamente, sem derrubar conexões ativas de WebSocket ou requisições HTTP em execução.
- Em caso de arquivo corrompido ou erro de I/O, o reload falha de forma segura sem interromper o certificado em uso.

### **3.2 Suporte a SNI (Server Name Indication) Dinâmico**
- **Recurso**: Suporte a múltiplos certificados SSL no mesmo socket/porta escutada.
- **Configuração Declarativa**:
  ```pascal
  Server.SSL.AddCertificate('*.dext.dev', '/etc/certs/dext-wildcard.pem', '/etc/certs/dext-wildcard.key');
  Server.SSL.AddCertificate('api.empresa.com', '/etc/certs/api.pem', '/etc/certs/api.key');
  ```

### **3.3 Shield Assíncrono contra Ataques Slowloris no Event Loop**
- **Comportamento**: A parsing inicial dos cabeçalhos HTTP e do Handshake de TLS/WebSocket ocorre de forma assíncrona dentro do Event Loop (`epoll` / `WSAPoll`).
- Apenas quando o cabeçalho completo é recebido é que a requisição é despachada para o Worker Thread Pool.
- Conexões lentas ou maliciosas não consomem Worker Threads do servidor.

---

## 📅 4. Cronograma de Implementação
1. **Fase 1**: Validação e atualização das referências nas especificações e índices do repositório.
2. **Fase 2**: Implementação do módulo de `ReloadCertificates` e `SNI Engine` no módulo `Dext.Net.Security`.
3. **Fase 3**: Benchmark comparativo formal Dext vs. Sparkle Socket Server em ambiente Ubuntu Linux.