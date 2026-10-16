# Estratégia de Produto e Arquitetura: Dext Testing no C++Builder

> **Status:** deep research 2 (input). Decisões operacionais: [Dext-Testing-Cpp-Discovery.md](Dext-Testing-Cpp-Discovery.md).  
> **Atenção:** §5.2 inventa flags `--dext-host` / `--dext-port` e JSON de exemplo. O Explorer Delphi hoje usa `--port N -no-wait` + protocolo do Host — alinhar o adapter ao contrato **real** antes de implementar.  
> **Ship (pós-research):** Expert distribuído como **DLL** + instalador (não só BPL) — C++ sem monorepo; isolamento quando o usuário recompila packages Dext. Ver Cpp-Discovery § Empacotamento.

## Pergunta Central de Produto: Qual o melhor caminho?

Para um desenvolvedor C++Builder no RAD Studio (10.4, 12 e 13), a estratégia de produto ideal é a **Opção 1 + Opção 2 Mínima: "Expert Universal + Adapters e Ponte de Protocolo"**.

Criar um **"Dext Testing C++ Completo" (Opção 3)** é uma **armadilha de escopo** por três motivos principais:

1. **Padrões de mercado consolidados:** O ecossistema C++ já padronizou o **Google Test (gtest)** para testes unitários e o **Google Mock (gmock)** para isolamento de dependências. A própria Embarcadero distribui e recomenda o Google Test via GetIt.


2. **Modelo do Visual Studio:** O Visual Studio Test Explorer não reinventa asserções para C++. Ele funciona como um *host* neutro que descobre e executa testes via adaptadores para Google Test, Boost.Test e Catch2.
3. **Complexidade sem ganho de valor:** Tentar replicar o `Mock<T>` e a sintaxe RTTI do Delphi em C++ exigiria reimplementar uma biblioteca complexa de metaprogramação, concorrendo diretamente contra o `gmock` sem oferecer diferenciação real para o desenvolvedor.



### Onde está o valor real do Dext no C++Builder?

O verdadeiro diferencial do Dext é o **Dext Test Explorer** (a experiência de TDD dentro da IDE). O desenvolvedor C++Builder sofre com a falta de um Test Explorer moderno e integrado na IDE. Ao oferecer o Explorer conversando com o Google Test e o DUnit C++, o Dext resolve a dor da interface visual sem forçar o desenvolvedor a mudar o framework de asserções que ele já utiliza.

---

## Bloco 1 — Limitações Delphi ↔ C++Builder (Interop e Tooling)

### 1.1 "Mesma IDE, duas personalidades"

O RAD Studio é um ambiente genérico gerenciado pela Open Tools API (OTA). Uma única BPL de design escrita em Delphi (`Dext.Testing.Design.bpl`) instalada na IDE pode manipular projetos de qualquer personalidade.

* **Acesso aos Projetos (`IOTAProject`):** A interface `IOTAProject` representa o projeto aberto (seja `.dproj` ou `.cbproj`). A propriedade `IOTAProject.Personality` indica a linguagem.


* **Compilação:** O Expert não precisa saber compilar código C++. Ele aciona a compilação chamando `IOTAProject.CompileProject` ou invocando o MSBuild em segundo plano no arquivo `.cbproj`.


* **Notificações do Editor:** As interfaces da OTA (`IOTAEditorServices`, `INTAEditViewNotifier`) funcionam de forma idêntica para arquivos `.pas`, `.cpp` ou `.h`.



### 1.2 Interoperabilidade Binária Delphi ↔ C++

A arquitetura do Dext Test Explorer — baseada na execução do binário de teste como um processo filho que se comunica via **socket TCP local (`--port N`)** — **elimina a necessidade de interoperabilidade binária** entre Delphi e C++.

* **Processo do Teste (`.exe` C++ puro):** Compilado 100% pelo C++Builder (`bcc64x` / `bcc32`).


* **Processo da IDE (`bds.exe` Delphi):** Carrega o `Dext.Testing.Design.bpl`.


* **Comunicação:** O Expert abre um servidor TCP local na IDE. O executável C++ conecta nessa porta e envia eventos em JSON. Não há compartilhamento de memória, exportação de rotinas via DLL, nem necessidade de arquivos `.hpp` gerados do Delphi.



### 1.3 Compiladores: Classic (`bcc32`) vs Clang (`bcc64x`)

No RAD Studio 12 e 13, a Embarcadero introduziu a nova *toolchain* Win64 baseada em Clang moderno (Clang 15+).

* **Classic (`bcc32`):** Compilador legado de 32 bits. Suporta DUnit C++ antigo, mas falha com C++ moderno.


* **Clang (`bcc64x`):** Padrão do RAD Studio 12/13. É o alvo primário para o Google Test, Catch2 e ferramentas modernas.


* **Impacto no Expert:** Nulo. Como a comunicação é via socket/IPC, a arquitetura do compilador que gerou o `.exe` é irrelevante para a IDE.



### 1.4 Confirmação das Constantes da Open Tools API

Na unidade `ToolsAPI.pas`, a constante oficial é:

```pascal
sCBuilderPersonality: string = 'CPlusPlusBuilder.Personality';

```

* **Fato:** O nome da constante no código Pascal é `sCBuilderPersonality` e seu valor string é `'CPlusPlusBuilder.Personality'`. Nomes como `sCppBuilderPersonality` são incorretos.


* **GetIt Package Manager:** Ao registrar o pacote de IDE no GetIt ou na chave do Registro do Windows, a personalidade informada deve ser `CPlusPlusBuilder.Personality` ou `Delphi.Personality`.

### Classificação de Premissas (Bloco 1)

| Declaração | Classificação | Detalhes |
| --- | --- | --- |
| Mesma BPL Delphi pode atender Delphi e C++Builder | **Fato** | Experts OTA em Delphi rodam no `bds.exe` e inspecionam qualquer `IOTAProject`.

 |
| Nome da constante é `sCBuilderPersonality` | **Fato** | Definido oficialmente em `ToolsAPI.pas`.

 |
| Não é necessário código C++ dentro da BPL do Expert | **Fato** | A IDE usa apenas a BPL Delphi. O código C++ vive apenas no projeto de teste do usuário.

 |
| MSBuild compila `.cbproj` via `IOTAProject.CompileProject` | **Precisa validar** | Testar se `CompileProject` aciona corretamente as dependências de *build* do Clang Win64 no RAD Studio 12/13.

 |

---

## Bloco 2 — "Attributes" e Metaprogramação em C++ (vs Delphi RTTI)

### 2.1 Attributes em C++ vs Delphi RTTI

* **Delphi RTTI:** O compilador Delphi gera metadados em tempo de execução para classes e métodos marcados com atributos (`[Test]`). A RTTI permite percorrer as classes carregadas e invocar métodos dinamicamente.


* **C++ Attributes (`[[...]]`):** No C++11/17/20, sintaxes como `[[nodiscard]]` ou `[[deprecated]]` destinam-se ao compilador e **não geram metadados de reflexão em tempo de execução**. O C++ não possui reflexão dinâmica nativa (*Reflection TS* ainda não é padrão funcional no C++Builder).



### 2.2 Como frameworks C++ descobrem testes

Frameworks C++ como Google Test, Catch2 e doctest utilizam o padrão de **Registro Estático via Macros e Construtores Globais**:

```cpp
// Exemplo de expansão conceitual da macro TEST(Suite, Nome)
static void Teste_Soma();
static bool registrador_Soma = []() {
    GlobalTestRegistry::Add("Suite", "Nome", &Teste_Soma);
    return true;
}();

```

Quando o `.exe` é iniciado, o *runtime* do C++ executa os inicializadores estáticos **antes de entrar na função `main()**`, preenchendo uma lista em memória com todos os testes cadastrados.

### 2.3 Por que não há DUnitX nativo em C++Builder?

O DUnitX apoia-se em recursos exclusivos da linguagem Delphi:

1. **Instanciação dinâmica por RTTI estendida**.


2. **Genéricos atrelados à RTL Delphi** (`TList<T>`, `Dictionary`).


3. **Métodos anônimos Pascal** (`reference to procedure`).



Como esses recursos não possuem equivalência de ABI no C++Builder Clang, o DUnitX não foi portado para C++ pela Embarcadero.

### 2.4 Conclusão Prática

**Não tente portar a descoberta por RTTI para C++.** O caminho correto é utilizar um **Adapter/Listener** sobre os frameworks C++ existentes (Google Test e DUnit C++).

---

## Bloco 3 — Matriz de Reutilização de Recursos do Dext Testing

| Capacidade Delphi | Decisão de Produto | Mecanismo no C++Builder |
| --- | --- | --- |
| **Test Explorer (OTA, árvore, run, stack)** | **Manter 100% (Núcleo do Valor)** | A BPL Delphi na IDE consome os eventos JSON vindo do `.exe` C++ via Socket.

 |
| **Protocolo Host (`--port N`, JSON)** | **Manter 100% (Contrato)** | O `.exe` C++ conecta no servidor TCP local e envia o fluxo de eventos JSON.

 |
| **Adapter Google Test (gtest)** | **Criar (Prioridade 1)** | Classe `DextGTestListener` que traduz os eventos do GTest para o protocolo do Host.

 |
| **Adapter DUnit C++** | **Criar (Prioridade 2)** | Interceptador para o `GUITestRunner` do DUnit C++ legado.

 |
| **Runner nativo `Should` / `DextTesting.hpp**` | **Não Fazer (Armadilha)** | Descartado. O usuário escreverá testes em Google Test ou DUnit C++.

 |
| **Dext.Mocks** | **Substituir** | Recomendar o **Google Mock (`gmock`)**, distribuído com o GTest no GetIt.

 |
| **Snapshots (`MatchSnapshot`)** | **Adiar (Pós-MVP)** | Pode ser oferecido como uma biblioteca header-only mínima no futuro. |
| **Relatórios CI (JUnit/Sonar/HTML)** | **Manter via CLI** | O utilitário `dext.exe` executa o `.exe` C++ e gera relatórios a partir da saída JSON/XML.

 |
| **Coverage Gutter** | **Manter via LLVM** | Para Clang Win64 (`bcc64x`), compilar com `-fprofile-instr-generate` e processar via `llvm-cov`.

 |
| **WebApplicationFactory** | **Fora de Escopo** | Não se aplica ao perfil de uso típico do C++Builder. |

---

## Bloco 4 — Recomendação de MVP e Anti-Objetivos

### Horizontes de Desenvolvimento

#### 1. MVP (Semanas)

* Habilitar `sCBuilderPersonality` na rotina de registro do `Dext.Testing.Design.bpl`.


* Suportar compilação e descoberta de projetos `.cbproj`.


* Disponibilizar o arquivo de cabeçalho `DextGTestAdapter.hpp` (Listener do Google Test que conecta via TCP no Host da IDE).


* Validar a execução de uma suíte Google Test no C++Builder 12/13 Win64 (`bcc64x`).



#### 2. Próximo (Meses)

* Adapter para DUnit C++ legado (suporte a projetos legados `bcc32`).


* Cobertura de código para C++ Clang Win64 via `llvm-cov`.


* Adapter experimental para Catch2 / doctest.



#### 3. Anti-Objetivos (O que NÃO fazer)

* **NÃO** criar um segundo BPL em C++ para a IDE.
* **NÃO** criar um framework próprio de asserções fluentes (`Should`) ou Mocks em C++.
* **NÃO** tentar carregar a RTL Delphi dentro do executável C++ de testes.
* **NÃO** inventar um protocolo IPC novo; utilizar estritamente o protocolo JSON sobre TCP que o Host Dext já utiliza.



### Diagrama Arquitetural da Solução

* **IDE RAD Studio (`bds.exe`)**
* **Dext Test Explorer (`Dext.Testing.Design.bpl` - Delphi)**
* Inspeciona projetos Delphi (`.dproj`) e C++Builder (`.cbproj`).


* Abre o Servidor TCP Host na porta dinâmica `N`.


* Invoque o MSBuild para compilar o projeto `.cbproj`.


* Inicia o processo filho: `MeuProjetoTestes.exe --dext-host 127.0.0.1 --dext-port N`.






* **Processo Filho Isoliado (`MeuProjetoTestes.exe` - C++ Puro)**
* Código do Desenvolvedor (Testes Google Test / `gtest`).


* **`DextGTestAdapter.hpp` (Header-only)**
* Conecta no Socket TCP `127.0.0.1:N`.


* Registra o Listener no Google Test (`::testing::UnitTest::GetInstance()->listeners().Append(...)`).


* Envia o fluxo JSON de eventos (Discovery, TestStart, TestPass, TestFail, StackTrace).







---

## Bloco 5 — Adapter Google Test (Implementação de Engenharia)

### 5.1 Mecanismo de Integração do Google Test

O Google Test possui uma API nativa de observação baseada em `testing::EmptyTestEventListener`. O adaptador do Dext deriva dessa classe e intercepta os eventos de execução sem alterar os testes do usuário.

### 5.2 Fluxo do Protocolo IPC (Socket TCP JSON)

Quando executado com as opções `--dext-host 127.0.0.1 --dext-port <PORTA>`, o adaptador abre uma conexão TCP Socket cliente.

O fluxo de mensagens enviadas para a IDE segue a estrutura simplificada:

1. **Handshake:** `{"cmd": "connect", "client": "gtest-cpp"}`
2. **Discovery (Árvore):** `{"event": "discovery", "fixtures": [...]}`
3. **Início do Teste:** `{"event": "test_start", "fixture": "CalculadoraTest", "test": "Soma"}`
4. **Resultado (Falha):** `{"event": "test_finish", "fixture": "CalculadoraTest", "test": "Soma", "status": "failed", "message": "Expected 30, got 25", "file": "TestCalc.cpp", "line": 42}`
5. **Finalização:** `{"cmd": "disconnect"}`

### 5.3 Limitações Conhecidas do Google Test no C++Builder

* **Death Tests (`EXPECT_DEATH`):** O Google Test tenta fazer `fork()` ou criar novos processos para testar colisões/crashes. No Windows/C++Builder, isso pode falhar ou fechar a conexão de socket prematuramente.
* **Filtros de Execução:** Para rodar apenas o teste selecionado na IDE, o adaptador deve repassar a flag `--gtest_filter=Suite.Nome` ao Google Test.
* **Erros de Linkagem em DLLs:** O Google Test estático exige runtime compatível (`/MT` vs `/MD`). No C++Builder Clang, recomenda-se compilar os fontes do GTest diretamente dentro do projeto de testes.



### 5.4 Esqueleto Mínimo do Adapter C++ (`DextGTestAdapter.hpp`)

```cpp
#ifndef DextGTestAdapterHPP
#define DextGTestAdapterHPP

#include <gtest/gtest.h>
#include <winsock2.h>
#include <ws2tcpip.h>
#include <iostream>
#include <string>

#pragma comment(lib, "ws2_32.lib")

namespace Dext {
    namespace Adapters {

        class DextGTestListener : public ::testing::EmptyTestEventListener {
        private:
            SOCKET FSocket;

            void SendJson(const std::string& jsonMessage) {
                if (FSocket != INVALID_SOCKET) {
                    std::string payload = jsonMessage + "\n";
                    send(FSocket, payload.c_str(), static_cast<int>(payload.length()), 0);
                }
            }

        public:
            DextGTestListener(const std::string& host, int port) : FSocket(INVALID_SOCKET) {
                WSADATA wsaData;
                if (WSAStartup(MAKEWORD(2, 2), &wsaData) == 0) {
                    FSocket = socket(AF_INET, SOCK_STREAM, IPPROTO_TCP);
                    sockaddr_in clientService;
                    clientService.sin_family = AF_INET;
                    inet_pton(AF_INET, host.c_str(), &clientService.sin_addr);
                    clientService.sin_port = htons(port);

                    if (connect(FSocket, (SOCKADDR*)&clientService, sizeof(clientService)) == SOCKET_ERROR) {
                        closesocket(FSocket);
                        FSocket = INVALID_SOCKET;
                    }
                }
            }

            ~DextGTestListener() {
                if (FSocket != INVALID_SOCKET) {
                    closesocket(FSocket);
                    WSACleanup();
                }
            }

            void OnTestStart(const ::testing::TestInfo& test_info) override {
                std::string msg = "{\"event\":\"test_start\",\"fixture\":\"" + 
                                  std::string(test_info.test_suite_name()) + 
                                  "\",\"test\":\"" + test_info.name() + "\"}";
                SendJson(msg);
            }

            void OnTestPartResult(const ::testing::TestPartResult& test_part_result) override {
                if (test_part_result.failed()) {
                    // Captura de falhas e localização de arquivo/linha
                }
            }

            void OnTestEnd(const ::testing::TestInfo& test_info) override {
                std::string status = test_info.result()->Passed() ? "passed" : "failed";
                std::string msg = "{\"event\":\"test_finish\",\"fixture\":\"" + 
                                  std::string(test_info.test_suite_name()) + 
                                  "\",\"test\":\"" + test_info.name() + 
                                  "\",\"status\":\"" + status + "\"}";
                SendJson(msg);
            }
        };

        // Função utilitária para inicializar a integração no main()
        inline void InitDextGTest(int& argc, char** argv) {
            ::testing::InitGoogleTest(&argc, argv);
            
            std::string host = "";
            int port = 0;

            for (int i = 1; i < argc; ++i) {
                std::string arg = argv[i];
                if (arg == "--dext-host" && i + 1 < argc) host = argv[++i];
                if (arg == "--dext-port" && i + 1 < argc) port = std::stoi(argv[++i]);
            }

            if (!host.empty() && port > 0) {
                auto& listeners = ::testing::UnitTest::GetInstance()->listeners();
                listeners.Append(new DextGTestListener(host, port));
            }
        }
    }
}

#endif

```

### Exemplo do Ponto de Entrada do Teste (`File1.cpp`)

```cpp
#include <vcl.h>
#pragma hdrstop
#include "DextGTestAdapter.hpp"

TEST(CalculadoraSuite, TesteSoma) {
    EXPECT_EQ(30, 10 + 20);
}

int main(int argc, char* argv[]) {
    // Inicializa o Google Test e anexa o Listener do Dext se invocado pela IDE
    Dext::Adapters::InitDextGTest(argc, argv);
    
    // Executa a suíte
    return RUN_ALL_TESTS();
}

```

---

## Checklist de Experimentos para Validação no RAD Studio

1. **[ ] Instalação da BPL na Personalidade C++:** Compilar o `Dext.Testing.Design.dpk` no RAD Studio 12/13 e verificar se o menu/painel do Test Explorer permanece visível ao alternar para um projeto C++Builder.


2. **[ ] Captura de Projetos `.cbproj`:** Abrir um grupo contendo um projeto `.cbproj` e confirmar se `IOTAProject.Personality` retorna `'CPlusPlusBuilder.Personality'` (`sCBuilderPersonality`).


3. **[ ] Compilação via MSBuild:** Chamar a compilação do `.cbproj` a partir do menu de contexto do Expert e validar se o binário `.exe` é gerado na pasta de saída (`Win64/Debug`).


4. **[ ] Comunicação TCP Socket:** Executar o `DextGTestAdapter.hpp` apontando para o IP/porta do Expert e validar o preenchimento da árvore de testes na IDE.


5. **[ ] Teste de Cobertura Clang Win64:** Compilar um projeto C++ com as flags `-fprofile-instr-generate -fcoverage-mapping` no `bcc64x`, rodar o teste e validar se o `llvm-cov` gera o arquivo legível para o Dext CLI.