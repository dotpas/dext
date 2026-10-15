# **Arquitetura e Estratégia de Integração do Dext Testing Framework na Personalidade C++Builder do RAD Studio**

## **Contexto e Ecossistema do Dext Testing Framework**

O Dext Testing Framework foi concebido como uma solução de testes unitários e de integração para o ecossistema RAD Studio, fornecendo um ambiente produtivo para a prática de Test-Driven Development (TDD)1. A arquitetura da ferramenta combina um motor de execução orientado a atributos, asserções fluentes por meio da interface Should(), mocking dinâmico via Dext.Mocks, testes de snapshot e geradores de relatórios padronizados para integração contínua nos formatos JUnit, xUnit, TRX, SonarQube e HTML1.  
A experiência visual do desenvolvedor na IDE do RAD Studio é provida pelo **Dext Test Explorer**, um plugin (Expert) desenvolvido com a Open Tools API (OTA)1. O Expert é carregado diretamente no processo principal da IDE (bds.exe) e expõe recursos como descoberta de testes, execução seletiva por fixtures ou métodos, inspetor de falhas com suporte a *stack trace*, alternância de agrupamentos e links diretos para as linhas de código no editor1.  
A arquitetura do Dext Test Explorer adota um modelo de execução desacoplado2. A IDE não executa o código do teste diretamente em seu próprio espaço de memória; em vez disso, ela gerencia a compilação do projeto de testes e orquestra a execução de um processo binário filho2. A comunicação entre o Test Explorer e a suíte de testes ocorre por meio de parâmetros de linha de comando e fluxos de dados estruturados em JSON ou XML2. Essa abordagem garante o isolamento do processo da IDE contra falhas de memória ou *crashes* provocados pelos testes2.  
O suporte estendido a frameworks legados na linguagem Delphi — como DUnit, DUnitX e DUnit2 — é viabilizado por meio do padrão *Adapter*2. O projeto de teste inclui a unidade Dext.Testing.Integration e intercepta a inicialização da linha de comando com a instrução TTestRunnerRegistry.TryExecuteFromCommandLine2. Se a IDE invocar o executável com parâmetros de comunicação do Dext, o interceptador assume o controle, executa os testes e reporta os resultados para o painel visual da IDE2.  
A expansão dessa infraestrutura para a personalidade **C++Builder** (sCppBuilderPersonality) exige mapear o ecossistema de testes unitários C++, adaptar o Expert escrito em Delphi para reconhecer projetos C++ e construir uma ponte de interoperabilidade nativa em C++.

## **Ecossistema de Testes Unitários no C++Builder**

Para fundamentar a estratégia de integração do Dext na personalidade C++Builder, é necessário analisar os frameworks de teste utilizados por desenvolvedores C++ no RAD Studio. Ao contrário do Delphi, onde o DUnitX e o DUnit constituem os padrões históricos predominantemente adotados, o ecossistema C++Builder apresenta uma coexistência entre invólucros C++ legados e bibliotecas C++ modernas multiplataforma3.

### **Frameworks Utilizados em Projetos C++Builder**

* **Google Test (gtest) / Google Mock (gmock)**: É a principal solução moderna recomendada pela Embarcadero e disponibilizada diretamente pelo gerenciador de pacotes **GetIt**3. Possui suporte aos compiladores modernos baseados em Clang no C++Builder5. O Google Test oferece suporte a *fixtures*, parametrização de testes, testes de morte (*death tests*) e mocking avançado com a biblioteca Google Mock5.  
* **DUnit (Versão C++)**: Historicamente incluído no RAD Studio para C++Builder, o DUnit C++ é composto por arquivos de cabeçalho C++ (TestFramework.hpp, GUITestRunner.hpp, XMLTestRunner.hpp) acoplados ao binário compilado em Pascal (dunitrtl.lib)3. Embora funcione tanto com os compiladores clássicos quanto com as cadeias Clang, apresenta limitações com construções C++ modernas e sofre com a ausência de evolução ativa10.  
* **Catch2**: Disponível via GetIt, o Catch2 é uma biblioteca moderna voltada para C++20/C++17, bastante difundida por utilizar asserções baseadas em expressões booleanas naturais e seções encadeadas para setup e teardown local4.  
* **doctest**: Distribuído via GetIt, destaca-se pela velocidade de compilação e baixo impacto no tempo de *build*4. Permite que os testes sejam inseridos diretamente no código de produção ou agrupados em suítes independentes4.  
* **Boost.Test**: Integrado às bibliotecas Boost disponibilizadas para o C++Builder, é indicado para projetos industriais que já utilizam a infraestrutura da Boost5.

### **Incompatibilidade do DUnitX com C++Builder**

O framework DUnitX apoia-se em recursos da linguagem Delphi, tais como atributos RTTI estendidos, genéricos vinculados à linguagem Pascal e métodos anônimos (reference to procedure)3. Como essas construções não possuem mapeamento direto de ABI (Application Binary Interface) nem equivalência de cabeçalhos nos compiladores Clang para C++, o DUnitX não é suportado nativamente na personalidade C++Builder em versões recentes do RAD Studio3.

| Framework de Teste | Disponibilidade em C++Builder | Suporte a Toolchain Clang / Win64 | Capacidade de Mocking | Viabilidade de Adaptação ao Dext Explorer |
| :---- | :---- | :---- | :---- | :---- |
| **Google Test (gtest)** | Integrado via GetIt Package Manager5 | Total (Clang15+ no RAD Studio 12/13)7 | Excelente (via Google Mock)5 | Altíssima (adapter padrão sugerido via Listener/JSON) |
| **DUnit (C++)** | Incluído no RAD Studio3 | Parcial / Legado3 | Limitada10 | Total (mesmo protocolo do DUnit Pascal do Dext)2 |
| **Catch2** | Disponível via GetIt Package Manager4 | Total4 | Exige biblioteca externa | Média (requer repórter de eventos customizado) |
| **doctest** | Disponível via GetIt Package Manager4 | Total4 | Exige biblioteca externa | Média (suporta repórteres customizados) |
| **Boost.Test** | Nativo via ecossistema Boost5 | Total9 | Média (módulos Boost) | Média (requer conversor de saída de console) |
| **DUnitX** | Indisponível para C++3 | Sem suporte em C++3 | Indisponível em C++ | Baixa (incompatibilidade estrutural com RTTI Pascal)3 |

## **Arquitetura da Integração no RAD Studio via Open Tools API**

O Dext Test Explorer é um pacote Delphi registrado no ambiente de desenvolvimento que estende as capacidades da IDE por meio da Open Tools API (OTA)1. Como o ambiente RAD Studio utiliza um núcleo integrado para gerenciar múltiplos projetos, o Expert pode inspecionar e interagir com projetos de qualquer linguagem suportada pela ferramenta13.

### **Identificação da Personalidade C++Builder (sCppBuilderPersonality)**

A Open Tools API representa cada projeto carregado na IDE por meio da interface IOTAProject15. A linguagem e o modelo de projeto são identificados pela propriedade Personality15. Enquanto os projetos Delphi utilizam a constante sDelphiPersonality, os projetos do C++Builder são identificados pela constante sCppBuilderPersonality (cujo GUID interno é "{E18FA059-CC68-4547-B08F-EF1D03C5A03A}")15.  
Para habilitar o suporte ao C++Builder no Dext Test Explorer, o código do Expert em Delphi deve ser ajustado para aceitar ambas as personalidades na rotina de validação do projeto ativo:

Delphi  
function IsDextSupportedProject(const AProject: IOTAProject): Boolean;  
begin  
  Result := Assigned(AProject) and   
            (SameText(AProject.Personality, sDelphiPersonality) or   
             SameText(AProject.Personality, sCppBuilderPersonality));  
end;

Essa alteração permite que o Expert leia arquivos com extensão .cbproj (C++Builder Project), monitore a árvore de arquivos de código-fonte (.cpp, .h, .hpp) e invoque os processos de compilação da IDE via MSBuild (IOTAProject.CompileProject) de forma análoga ao que é feito com projetos .dproj15.

### **Mecanismo de Descoberta de Testes (*Test Discovery*)**

Para montar a árvore visual de testes sem travar a interface da IDE, a descoberta de testes em projetos C++Builder deve ser realizada de forma assíncrona utilizando duas estratégias complementares:

> 1. **Descoberta Dinâmica por Protocolo Executável (Principal)**: O Expert compila o projeto de testes .cbproj e executa o binário resultante passando a flag \--dext-discover. A ponte C++ do Dext intercepta essa instrução no ponto de entrada do programa, analisa as *fixtures* registradas na memória da aplicação e emite a árvore estruturada de testes no formato JSON para o console ou para um arquivo temporário.  
> 2. **Descoberta Estática por Análise de Arquivos (Secundária)**: O Expert realiza a varredura dos arquivos .cpp e .hpp vinculados ao projeto .cbproj, buscando declarações de macros de teste (como TEST, TEST\_F, DEXT\_TEST ou DEXT\_TEST\_CASE). Essa abordagem permite construir uma visualização prévia da árvore no editor antes mesmo da primeira compilação do projeto.

## **Desenvolvendo a Ponte C++ (DextTesting.hpp) e Protocolos de Interoperabilidade**

Como o motor principal do Dext Testing foi desenvolvido em Pascal, a execução de testes em C++Builder exige a implementação de uma **Ponte de Compatibilidade C++** (*Dext C++ Bridge*). Essa ponte consiste em uma biblioteca de cabeçalhos (*header-only*) ou arquivo estático (.hpp / .lib) responsável por registrar os testes em C++, interceptar chamadas da linha de comando e reportar o progresso da execução para o Dext Test Explorer2.

### **Código da Ponte de Compatibilidade C++ (DextTesting.hpp)**

O código abaixo ilustra a estrutura funcional da ponte para registrar testes C++ e fornecer o protocolo de comunicação esperado pelo Dext:

C++  
\#**ifndef** DextTestingHPP  
\#**define** DextTestingHPP

\#**include** \<iostream\>  
\#**include** \<string\>  
\#**include** \<vector\>  
\#**include** \<functional\>  
\#**include** \<memory\>

namespace Dext {  
    namespace Testing {

        struct TestCaseInfo {  
            std::string FixtureName;  
            std::string TestName;  
            std::function\<void()\> TestProc;  
        };

        class TestRegistry {  
        public:  
            static TestRegistry& Instance() {  
                static TestRegistry instance;  
                return instance;  
            }

            void RegisterTest(const std::string& fixtureName, const std::string& testName, std::function\<void()\> proc) {  
                FTestCases.push\_back({fixtureName, testName, proc});  
            }

            bool TryExecuteFromCommandLine(int argc, char\* argv\[\]) {  
                for (int i \= 1; i \< argc; \++i) {  
                    std::string arg \= argv\[i\];  
                    if (arg \== "--dext-discover") {  
                        EmitDiscoveryJson();  
                        return true;  
                    }  
                    if (arg \== "--dext-run") {  
                        ExecuteRegisteredTests();  
                        return true;  
                    }  
                }  
                return false;  
            }

        private:  
            std::vector\<TestCaseInfo\> FTestCases;

            void EmitDiscoveryJson() {  
                std::cout \<\< "{\\"status\\":\\"ok\\",\\"engine\\":\\"cpp\\",\\"fixtures\\":\[";  
                // Serialização simplificada da estrutura de testes para o Dext Explorer  
                for (size\_t i \= 0; i \< FTestCases.size(); \++i) {  
                    std::cout \<\< "{\\"fixture\\":\\"" \<\< FTestCases\[i\].FixtureName   
                              \<\< "\\",\\"name\\":\\"" \<\< FTestCases\[i\].TestName \<\< "\\"}";  
                    if (i \+ 1 \< FTestCases.size()) std::cout \<\< ",";  
                }  
                std::cout \<\< "\]}" \<\< std::endl;  
            }

            void ExecuteRegisteredTests() {  
                // Execução e geração de relatório de saída para a IDE  
                for (const auto& test : FTestCases) {  
                    try {  
                        test.TestProc();  
                        std::cout \<\< "\[PASSED\] " \<\< test.FixtureName \<\< "." \<\< test.TestName \<\< std::endl;  
                    } catch (const std::exception& ex) {  
                        std::cout \<\< "\[FAILED\] " \<\< test.FixtureName \<\< "." \<\< test.TestName   
                                  \<\< " Reason: " \<\< ex.what() \<\< std::endl;  
                    } catch (...) {  
                        std::cout \<\< "\[FAILED\] " \<\< test.FixtureName \<\< "." \<\< test.TestName   
                                  \<\< " Unknown exception" \<\< std::endl;  
                    }  
                }  
            }  
        };

        // Abstração da sintaxe fluente de Asserções (Should)  
        template \<typename T\>  
        class FluentAssertion {  
        private:  
            T FValue;  
        public:  
            FluentAssertion(T val) : FValue(val) {}

            void Be(T expected) {  
                if (FValue \!= expected) {  
                    throw std::runtime\_error("Assertion Failed: Values are not equal.");  
                }  
            }

            void NotBe(T expected) {  
                if (FValue \== expected) {  
                    throw std::runtime\_error("Assertion Failed: Values are equal.");  
                }  
            }  
        };

        template \<typename T\>  
        FluentAssertion\<T\> Should(T val) {  
            return FluentAssertion\<T\>(val);  
        }  
    }  
}

// Macro para interceptar o ponto de entrada principal do projeto de testes  
\#**define** DEXT\_RUN\_TESTS(argc, argv) \\  
    **if** (Dext::Testing::TestRegistry::Instance().TryExecuteFromCommandLine(argc, argv)) { \\  
        return 0; \\  
    }

// Macro helper para registrar métodos de teste em C++  
\#**define** DEXT\_TEST(fixtureName, testName) \\  
    void fixtureName\#\#\_\#\#testName(); \\  
    struct Register\_\#\#fixtureName\#\#\_\#\#testName { \\  
        Register\_\#\#fixtureName\#\#\_\#\#testName() { \\  
            Dext::Testing::TestRegistry::Instance().RegisterTest(\#fixtureName, \#testName, fixtureName\#\#\_\#\#testName); \\  
        } \\  
    } instance\_\#\#fixtureName\#\#\_\#\#testName; \\  
    void fixtureName\#\#\_\#\#testName()

\#**endif**

### **Exemplo de Aplicação em Projeto Console C++Builder**

No arquivo principal do aplicativo de testes C++ (File1.cpp), o desenvolvedor inclui a ponte e registra o ponto de interceptação do Dext:

C++  
\#**include** \<vcl.h\>  
\#**pragma** hdrstop  
\#**include** "DextTesting.hpp"

// Exemplo de escrita de teste usando as macros e asserções da ponte Dext  
DEXT\_TEST(CalculadoraTests, Deve\_Somar\_Dois\_Numeros)  
{  
    int resultado \= 10 \+ 20;  
    Dext::Testing::Should(resultado).Be(30);  
}

int main(int argc, char\* argv\[\])  
{  
    // Intercepta e responde aos comandos do Dext Test Explorer na IDE  
    DEXT\_RUN\_TESTS(argc, argv);

    // Fluxo padrao de execução caso seja aberto via terminal  
    std::cout \<\< "Executando testes via terminal..." \<\< std::endl;  
    return 0;  
}

## **Matriz de Paridade de Funcionalidades, Viabilidade e Limitações Técnicas**

A transição das funcionalidades do ecossistema Delphi para a personalidade C++Builder envolve restrições decorrentes do modelo de metadados das linguagens. Enquanto o Delphi disponibiliza reflexão em tempo de execução via RTTI estendida, o C++ depende do modelo de compilação estática com metaprogramação por *templates* e macros de pré-processamento.

### **Análise Detalhada dos Recursos do Dext Framework**

> 1. **Atributos (\[Test\], \[TestCase\])**: No Delphi, o Dext utiliza atributos RTTI para identificar métodos de teste e injetar parâmetros1. Em C++, essa capacidade é mapeada por meio de macros de pré-processamento (DEXT\_TEST, DEXT\_TEST\_CASE) que registram as funções em uma lista estática antes da execução da função main()9.  
> 2. **Asserções Fluentes (Should())**: A sintaxe Should() do Dext pode ser replicada em C++ por meio de classes parametrizadas (*templates*) e sobrecarga de operadores2. Essa abordagem oferece equivalência funcional em relação à versão Delphi, incluindo asserções de igualdade, intervalos, coleções e tratamento de exceções.  
> 3. **Mocking Dinâmico (Dext.Mocks)**: A funcionalidade de mocking nativa do Dext (Mock\<T\>) utiliza registros genéricos e manipuladores de RTTI dinâmicos do Pascal (System.Rtti)2. Esse componente é incompatível com o compilador C++Builder. Em projetos C++, o mocking é provido pela integração com o **Google Mock (gmock)**, biblioteca recomendada pela Embarcadero5.  
> 4. **Testes de Snapshot (MatchSnapshot)**: O recurso de validação por snapshot pode ser disponibilizado em C++ criando utilitários de serialização JSON e comparação de arquivos em disco2. A ponte C++ do Dext pode ler e gravar arquivos .snapshot.json mantendo o mesmo padrão de nomenclatura do framework Delphi1.  
> 5. **Cobertura de Código (Code Coverage)**: A versão Delphi do Dext executa a análise de cobertura através do utilitário externo *Delphi Code Coverage*, que lê arquivos .map compilados2. Para o C++Builder 12 e 13 (cadeia de ferramentas Clang Win64 moderna), a cobertura de código é gerada via instrumentação nativa do compilador LLVM (-fprofile-instr-generate e \-fcoverage-mapping)8. O dext.exe CLI processa os arquivos de perfomance .profraw com as ferramentas llvm-profdata e llvm-cov, exportando os dados no formato XML consumível pelo SonarQube e pelo gutter visual do editor da IDE1.  
> 6. **WebApplicationFactory In-Process**: O suporte a testes de integração HTTP in-process no Delphi é acoplado aos componentes de infraestrutura do Dext Web1. Em C++, essa funcionalidade requer a criação de abstrações específicas sobre clientes HTTP locais ou sockets Win32.

| Funcionalidade Dext | Disponibilidade em C++Builder | Mecanismo de Implementação em C++ | Observações e Limitações |
| :---- | :---- | :---- | :---- |
| **Atributos de Teste** | Disponível via Macros | Macros de pré-processamento (DEXT\_TEST)9 | Substitui a RTTI Pascal por registro estático via construtores globais C++. |
| **Asserções Fluentes (Should)** | Disponível | Templates C++ com sobrecarga de métodos e operadores2 | Mantém paridade sintática e funcional com a API Delphi2. |
| **Mocking Dinâmico** | Substituído por Google Mock | Integração com a biblioteca gmock \[cite: 5\] | Dext.Mocks não compila em C++2. Recomenda-se utilizar o Google Mock disponibilizado no GetIt5. |
| **Testes de Snapshot** | Disponível | Funções de arquivo e serialização JSON | Requer vinculação com uma biblioteca JSON C++ (ex: nlohmann/json). |
| **Relatórios (JUnit, Sonar, HTML)** | Disponível | Gerados pela Ponte C++ ou pelo Dext CLI | O binário de teste ou a CLI converte os resultados da execução no formato XML/JSON especificado1. |
| **Cobertura de Código** | Disponível via LLVM | Instrumentação \-fprofile-instr-generate \+ llvm-cov \[cite: 8, 18\] | Substitui o *Delphi Code Coverage* pela infraestrutura nativa do Clang no C++Builder 12/132. |
| **Adapters de Terceiros** | Disponível (GoogleTest e DUnit C++) | Interceptadores via Event Listening no C++5 | Permite exibir testes GoogleTest e DUnit C++ no Dext Test Explorer2. |

## **Roteiro Prático de Implementação e Evolução do Framework**

A expansão do Dext Testing para a personalidade C++Builder do RAD Studio deve ser conduzida em quatro fases contínuas de desenvolvimento.

### **Fase 1: Atualização do Plugin Dext Test Explorer (Open Tools API)**

O objetivo desta etapa é permitir que o Expert carregado na IDE reconheça e interaja com projetos C++Builder.

* **Reconhecimento de Projetos C++**: Alterar as unidades de registro da IDE no Expert (Dext.Testing.Design.Explorer.pas) para aceitar a constante sCppBuilderPersonality além de sDelphiPersonality15.  
* **Gerenciamento de Arquivos .cbproj**: Atualizar os métodos de captura de arquivos do Expert para monitorar extensões .cbproj, mapeando o grafo de arquivos fontes .cpp e .hpp vinculados15.  
* **Compilação e Invocação**: Ajustar os comandos de execução do Expert para acionar o MSBuild com os parâmetros corretos do C++Builder, identificando se a saída do binário compilado encontra-se nas pastas de saída configuradas para a plataforma (ex: Win64/Debug/ProjetoTestes.exe)17.

### **Fase 2: Construção e Distribuição da Ponte DextTesting.hpp**

Nesta etapa, disponibiliza-se a estrutura de código necessária para que projetos C++Builder possam declarar e executar testes compatíveis com o Dext.

* **Criação da Biblioteca Header-Only**: Estruturar os arquivos da biblioteca em Sources/CPP/DextTesting.hpp.  
* **Implementação do Protocolo IPC**: Garantir que o método TryExecuteFromCommandLine responda adequadamente às flags \--dext-discover e \--dext-run, emitindo a estrutura JSON da suíte de testes2.  
* **Distribuição e Pacote GetIt**: Criar um instalador ou script de inclusão de caminho (*Search Path*) no RAD Studio para adicionar automaticamente a pasta de cabeçalhos C++ às configurações de novos projetos C++Builder.

### **Fase 3: Desenvolvimento dos Adapters para Google Test e DUnit C++**

Esta fase visa permitir que suítes de teste pré-existentes desenvolvidas em Google Test ou DUnit C++ sejam visualizadas e executadas pelo Dext Test Explorer3.

* **Adapter para Google Test**: Criar um ouvinte de eventos customizado (DextGTestListener) derivado da classe ::testing::EmptyTestEventListener do Google Test:  
  C++  
  class DextGTestListener : public ::testing::EmptyTestEventListener {  
      void OnTestEnd(const ::testing::TestInfo& test\_info) override {  
          // Reporta o resultado do teste no formato consumido pelo Dext Explorer  
      }  
  };

* **Interceptador DUnit C++**: Adicionar uma biblioteca de compatibilidade para interceptar a rotina GUITestRunner do DUnit C++ clássico e redirecionar os resultados para a interface do Dext Explorer2.

### **Fase 4: Automação da Cobertura de Código via Clang/LLVM**

A etapa final integra a análise de cobertura de código ao fluxo de trabalho do Dext CLI e ao editor visual do RAD Studio1.

* **Integração no Dext CLI (dext test \--coverage)**: Configurar o utilitário dext.exe para identificar quando o projeto alvo é do tipo C++Builder1.  
* **Injeção de Parâmetros de Profiling**: Adicionar as opções \-fprofile-instr-generate e \-fcoverage-mapping às opções do compilador bcc64x durante o *build* de cobertura8.  
* **Processamento de Relatórios**: Invocar o llvm-profdata para consolidar o arquivo .profraw e o llvm-cov para exportar o relatório no formato LCOV ou XML18.  
* **Exibição na IDE**: Converter o relatório LLVM gerado para o esquema padrão dext\_coverage.xml, permitindo que o Dext marque as linhas cobertas e não cobertas no editor de código da IDE1.

## **Conclusões e Recomendações Estratégicas**

> 1. **Acessibilidade do Plugin na IDE**: O Dext Test Explorer pode atuar com a personalidade C++Builder no RAD Studio1. Como o Expert é uma extensão Delphi que consome a Open Tools API, estender o suporte para projetos .cbproj exige o ajuste nos filtros de personalidade da interface IOTAProject e o suporte à execução dos binários C++ correspondentes13.  
> 2. **Arquitetura de Comunicação Desacoplada**: A melhor abordagem para conectar o Expert aos testes em C++ é adotar a arquitetura baseada na execução do binário de testes como processo separado, com troca de mensagens estruturadas em JSON/XML via linha de comando2. Essa abordagem evita a necessidade de vinculação binária direta entre os ambientes Delphi e C++, garantindo a estabilidade da IDE2.  
> 3. **Padrão de Frameworks para C++**: O Google Test (gtest) deve ser adotado como o framework C++ prioritário para suporte via *Adapter* no Dext Test Explorer5. Por ser a solução recomendada pela Embarcadero e mantida no gerenciador GetIt com suporte aos novos compiladores Clang, sua utilização atende aos projetos C++ modernos no RAD Studio5.  
> 4. **Alinhamento de Funcionalidades**: Recursos como visualização na IDE, organização por fixtures, asserções fluentes, relatórios consolidados (JUnit/SonarQube) e cobertura de código (via LLVM) são viáveis para C++Builder1. O mocking dinâmico provido pelo Dext.Mocks, por sua vez, deve ser substituído pelo Google Mock (gmock) em projetos C++, alinhando o ecossistema Dext às convenções de desenvolvimento da linguagem C++2.

#### **Referências citadas**

> 1. Dext-Testing-Features-Catalog-Draft.md  
> 2. README.md  
> 3. Unit Testing Overview \- RAD Studio \- Embarcadero DocWiki, [https\://docwiki.embarcadero.com/RADStudio/Alexandria/en/Unit\_Testing\_Overview](https://docwiki.embarcadero.com/RADStudio/Alexandria/en/Unit_Testing_Overview)  
> 4. framework | Embarcadero GetIt, [https\://getitnow.embarcadero.com/tag/framework/](https://getitnow.embarcadero.com/tag/framework/)  
> 5. Open Source C++ Libraries in C++Builder 10.4.2 \- Embarcadero Blogs, [https\://blogs.embarcadero.com/open-source-c-libraries-in-cbuilder-10-4-2/](https://blogs.embarcadero.com/open-source-c-libraries-in-cbuilder-10-4-2/)  
> 6. Google Test \- Embarcadero GetIt, [https\://getitnow.embarcadero.com/google-test/](https://getitnow.embarcadero.com/google-test/)  
> 7. Introducing Amazing CMake Support in C++Builder 12.2, [https\://blogs.embarcadero.com/introducing-amazing-cmake-support-in-cbuilder-12-2/](https://blogs.embarcadero.com/introducing-amazing-cmake-support-in-cbuilder-12-2/)  
> 8. Clang Toolchain in C++Builder 12.1 | PDF \- Scribd, [https\://www\.scribd.com/document/729216783/C-The-new-Clang-Toolchain-in-C-Builder-12-1](https://www.scribd.com/document/729216783/C-The-new-Clang-Toolchain-in-C-Builder-12-1)  
> 9. Introduction to Unit Testing and Test-Driven Development in C++, [https\://medium.com/@AlexanderObregon/introduction-to-unit-testing-and-test-driven-development-in-c-1a825a00b1b4](https://medium.com/@AlexanderObregon/introduction-to-unit-testing-and-test-driven-development-in-c-1a825a00b1b4)  
> 10. Google Tests (unit testing framework) working with Embarcadero, [https\://en.delphipraxis.net/topic/4347-google-tests-unit-testing-framework-working-with-embarcadero-c-clang-compiler/](https://en.delphipraxis.net/topic/4347-google-tests-unit-testing-framework-working-with-embarcadero-c-clang-compiler/)  
> 11. Learn How To Do Unit Testing In Delphi With The Powerful DUnitX, [https\://blogs.embarcadero.com/learn-how-to-do-unit-testing-in-delphi-with-the-powerful-dunitx-framework/](https://blogs.embarcadero.com/learn-how-to-do-unit-testing-in-delphi-with-the-powerful-dunitx-framework/)  
> 12. C++Builder11: How to unit test with googletest? \- Stack Overflow, [https\://stackoverflow.com/questions/73879934/cbuilder11-how-to-unit-test-with-googletest](https://stackoverflow.com/questions/73879934/cbuilder11-how-to-unit-test-with-googletest)  
> 13. Learn More About Open Tools API From These Experts, [https\://learndelphi.org/learn-more-about-open-tools-api-from-these-experts/](https://learndelphi.org/learn-more-about-open-tools-api-from-these-experts/)  
> 14. Quickly Learn About The Ultimate Open Tools APIs For Decorating, [https\://blogs.embarcadero.com/quickly-learn-about-the-ultimate-open-tools-apis-for-decorating-your-delphi-c-builder-ide/](https://blogs.embarcadero.com/quickly-learn-about-the-ultimate-open-tools-apis-for-decorating-your-delphi-c-builder-ide/)  
> 15. ToolsAPI.IOTAProject \- RAD Studio API Documentation, [https\://docwiki.embarcadero.com/Libraries/Florence/en/ToolsAPI.IOTAProject](https://docwiki.embarcadero.com/Libraries/Florence/en/ToolsAPI.IOTAProject)  
> 16. How to create new personality in the IDE using open tools API?, [https\://stackoverflow.com/questions/4722463/how-to-create-new-personality-in-the-ide-using-open-tools-api](https://stackoverflow.com/questions/4722463/how-to-create-new-personality-in-the-ide-using-open-tools-api)  
> 17. Compiling C++Builder project on command line \- Stack Overflow, [https\://stackoverflow.com/questions/4287566/compiling-cbuilder-project-on-command-line](https://stackoverflow.com/questions/4287566/compiling-cbuilder-project-on-command-line)  
> 18. Code coverage with llvm-cov \- Medium, [https\://medium.com/@sag50692/code-coverage-with-llvm-cov-16639b71f6a5](https://medium.com/@sag50692/code-coverage-with-llvm-cov-16639b71f6a5)  
> 19. Code Coverage \- The LLVM C Library, [https\://libc.llvm.org/dev/code\_coverage.html](https://libc.llvm.org/dev/code_coverage.html)