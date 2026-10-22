# 8. Testes

O Dext inclui um framework de testes poderoso inspirado no NUnit/xUnit, com mocking, assertions fluentes e test runner integrado.

## Capítulos

1. [Mocking](mocking.md) - `Mock<T>` para interfaces
2. [Assertions](assertions.md) - Sintaxe fluente `Should()`
3. [Snapshots](snapshots.md) - Testes de snapshot JSON
4. [Projetos não-Dext](projetos-nao-dext.md) - DUnit / DUnitX / DUnit2 no Explorer sem reescrever
5. [Test Explorer](test-explorer.md) - Instalação manual e cobertura de linha

## Estrutura do Projeto de Testes (.dpr)

Crie um projeto Console Application separado para os testes:

```pascal
program MeuProjeto.Testes;

{$APPTYPE CONSOLE}

uses
  Dext.MM,             // Opcional: Wrapper FastMM5
  Dext.Utils,          // SetConsoleCharSet, ConsolePause
  System.SysUtils,
  Dext.Testing,        // Facade principal (Assert, TTest, Should)
  MeusTestes in 'MeusTestes.pas';

begin
  try
    // Novo Runner Fluente Simplificado
    RunTests(ConfigureTests
      .Verbose             // Saída detalhada
      // .UseTestInsight   // Opcional: Força TestInsight mesmo fora da IDE
      // .UseDashboard     // Opcional: Inicia o Dashboard Web
      .RegisterFixtures([
        TDiscountServiceTests,
        TUsuarioServiceTests
      ])
    );
  except
    on E: Exception do
      Writeln('ERRO FATAL: ', E.ClassName, ': ', E.Message);
  end;
end.
```

## Escrevendo Testes (Atributos)

```pascal
uses
  Dext.Testing; // Facade única

type
  [TestFixture]
  TDiscountServiceTests = class
  public
    [Setup]
    procedure Setup;

    [TearDown]
    procedure TearDown;

    [Test]
    procedure Deve_Nao_Dar_Desconto_Para_Padrao;

    [Test]
    [TestCase(100.0, False, '', 0.0)]
    [TestCase(100.0, True, '', 10.0)]
    [TestCase(200.0, False, 'BLACKFRIDAY', 30.0)]
    procedure Deve_Calcular_Regras_Desconto(const Subtotal: Double; const IsVip: Boolean; const Coupon: string; const ExpectedDiscount: Double);
  end;
```

## Início Rápido

```pascal
uses
  Dext.Testing,   // Facade: Assert, Should, TTest
  Dext.Mocks;     // Mock<T> - record genérico, NÃO está na facade

type
  [TestFixture]
  TUsuarioServiceTests = class
  private
    FService: TUsuarioService;
    FMockRepo: Mock<IUsuarioRepository>;
  public
    [Setup]
    procedure Setup;

    [Test]
    procedure GetUsuario_RetornaUsuario_SeExiste;
  end;

procedure TUsuarioServiceTests.Setup;
begin
  FMockRepo := Mock<IUsuarioRepository>.Create;
  FService := TUsuarioService.Create(FMockRepo.Instance);
end;

procedure TUsuarioServiceTests.GetUsuario_RetornaUsuario_SeExiste;
var
  User: TUsuario;
begin
  // Arrange
  User := TUsuario.Create;
  User.Name := 'João';
  FMockRepo.Setup.Returns(User).When.FindById(Arg.Any<Integer>);

  // Act
  var Result := FService.GetById(1);

  // Assert
  Should(Result).NotBeNil;
  Should(Result.Name).Be('João');

  // Verify
  FMockRepo.Received(Times.Once).FindById(1);
end;
```

> [!IMPORTANT]
> `Mock<T>` é um **Record Genérico** — ele vive em `Dext.Mocks` (NÃO na facade `Dext.Testing`) e **NÃO** precisa de `.Free`.

## Assertions Fluentes

```pascal
// Valores Simples
Should(Total).Be(100);
Should(Nome).StartWith('Jo').AndAlso.EndWith('ão');

// Coleções
Should(Lista).Contain(Item);
Should(Lista).HaveCount(5);

// Exceções
Should(procedure begin Calc.DivByZero end).Throw<EInvalidOp>;

// Asserções Inteligentes (Fortemente Tipadas)
var u := Prototype.Entity<TUsuario>; // Entidade fantasma para metadados
Should(User).HaveValue(u.Name, 'Maria');
```

## Teste de Entidades (Aviso sobre Memória)

Ao testar entidades com coleções `OwnsObjects=False` (necessário para compatibilidade com ORM), **você deve liberar itens filhos manualmente** no `finally` do teste:

```pascal
var Pedido := TPedido.Create;
var Item := TItemPedido.Create;  // Criado manualmente
try
  Pedido.Itens.Add(Item);
  Pedido.CalcularTotal;
  // Assert...
finally
  Pedido.Free; // Libera Pedido e a Lista (mas NÃO o Item)
  Item.Free;   // OBRIGATÓRIO: Libera o item filho manualmente
end;
```

**Por quê?** Entidades usam `OwnsObjects = False` para evitar Double Free quando gerenciadas por um DbContext. Em testes unitários (sem DbContext), isso significa que objetos filhos devem ser liberados pelo testador.

## Testes de Integração (Scripts PowerShell)

Toda Web API deve ter um script de teste de integração PowerShell (ex: `Test.MeuProjeto.ps1`) na raiz do projeto.

### Estrutura Recomendada

1. Configuração (BaseURL, codificação UTF-8)
2. Health Check (valida se o servidor responde)
3. Auth / Geração de Token
4. Testes de casos de uso (CRUD, Fluxos de Negócio)
5. Validação de resultados (Códigos HTTP, conteúdo JSON)

### Dicas

- **Erros IPv6/404**: Use sempre `$baseUrl = "http://127.0.0.1:9000"` em vez de `localhost`
- **Headers**: Defina `Accept: application/json` e `Content-Type: application/json; charset=utf-8` explicitly
- **Enums**: Por padrão, o Dext serializes enums como strings (`"tsAberto"` e não `1`)
- **JWT**: Se a API usar JWT, inclua uma função `New-JwtToken` no script

## Integração com a IDE (Dext Test Explorer)

O Dext inclui suporte nativo de alto nível com o **Dext Test Explorer**, um Expert (plugin) completo para a IDE RAD Studio Delphi. Ele oferece uma interface visual interativa e integrada para descobrir, executar e analisar testes diretamente do seu ambiente de desenvolvimento.

### Funcionalidades do Test Explorer:
*   **Descoberta Automática**: Mapeia todas as fixtures e testes RTTI dinamicamente do arquivo de projeto `.dproj`.
*   **Modos de Agrupamento**: Alterne entre agrupamento por estrutura física de código (`Group by Code Structure`) ou status de execução (`Group by Test Status`).
*   **Layout Flexível**: Suporta visualização em Abas (`Tabbed Layout`) ou Layouts Divididos (`Split Bottom/Right Layout`).
*   **Test Inspector**: Exibe detalhes completos sobre o erro, stack trace, duração e localização física do teste. Dê duplo clique no teste para ir direto para a linha do código correspondente.
*   **Exportação Visual**: Menu integrado `...` que permite exportar relatórios diretamente para os formatos **JUnit XML**, **XUnit XML**, **JSON**, **SonarQube XML** ou **HTML Report**.

## Integração Nativa com DUnitX, DUnit e DUnit2

Se o seu projeto já utiliza o **DUnitX**, **DUnit** (clássico) ou **DUnit2** e você deseja visualizar e executar seus testes diretamente no **Dext Test Explorer**, você pode habilitar a integração nativa e desacoplada em poucos passos:

### Como configurar seu projeto de testes:

1. **Adicionar os Arquivos ao Path**: Certifique-se de que a pasta de fontes comuns do Dext (`\Sources\Common`) está presente nos caminhos de pesquisa (Search Path) do seu projeto.
2. **Definir a Diretiva do Compilador**: Adicione a diretiva correspondente ao seu framework nas configurações do projeto (ou no arquivo `Dext.inc`):
   * Para DUnitX: `DEXT_DUNITX`
   * Para DUnit: `DEXT_DUNIT`
   * Para DUnit2: `DEXT_DUNIT2`
3. **Atualizar a Cláusula Uses**: No seu arquivo `.dpr` (projeto principal), adicione as seguintes units:
   ```pascal
   {$IFDEF DEXT_DUNITX}
   Dext.Testing.Integration,
   Dext.Testing.DUnitX,
   {$ENDIF}
   {$IFDEF DEXT_DUNIT}
   Dext.Testing.Integration,
   Dext.Testing.DUnit,
   {$ENDIF}
   {$IFDEF DEXT_DUNIT2}
   Dext.Testing.Integration,
   Dext.Testing.DUnit2,
   {$ENDIF}
   ```
4. **Acionar o Interceptador de CommandLine**: No bloco principal (`begin ... end.`) do arquivo `.dpr`, antes de rodar o runner padrão, execute a verificação da linha de comando:
   ```pascal
   begin
     ReportMemoryLeaksOnShutdown := True;
     // ... outras inicializações ...

   {$IF (defined(DEXT_DUNITX) or defined(DEXT_DUNIT) or defined(DEXT_DUNIT2))}
     if TTestRunnerRegistry.TryExecuteFromCommandLine then
       Exit;
   {$ENDIF}

     // Código padrão de execução do DUnitX, DUnit ou DUnit2 (Console ou GUI)
     // ...
   end.
   ```

Essa abordagem permite que o **Dext Test Explorer** e o **Dext CLI** executem os testes passando parâmetros de comunicação em segundo plano de forma 100% desacoplada e livre de dependências pesadas na IDE.

---

## Integração Alternativa com TestInsight

Caso prefira, o Dext também mantém retrocompatibilidade com o plugin clássico **TestInsight** de Stefan Gliener para rodar os testes escritos no Dext.

### Como Habilitar o TestInsight:
1. Instale o [TestInsight](https://github.com/stefangliener/TestInsight).
2. Adicione a unit `Dext.Testing.TestInsight` na cláusula `uses` do seu arquivo `.dpr`.
3. O framework detectará automaticamente quando a execução for disparada via TestInsight.

## Cobertura de Código (Code Coverage)

O Dext possui suporte a análise de cobertura de código integrado à ferramenta open-source da comunidade **Delphi Code Coverage** (https://github.com/DelphiCodeCoverage/DelphiCodeCoverage). O utilitário `dext.exe` automatiza todo o setup, podendo baixar a última release diretamente do repositório se necessário, além de coordenar a execução e gerar os relatórios.

### Como Executar:
A análise de cobertura é executada de forma simples através da CLI do Dext:
```bash
dext test --coverage
```
Isso gerará relatórios consolidados em formatos compatíveis com analisadores de qualidade de código do mercado (como o SonarQube) e relatórios visuais estáticos (HTML).

> [!TIP]
> **Integração IDE**: a instalação manual do expert, o aviso sobre a DLL sem assinatura e a cobertura de linha no Win64x estão em [Test Explorer](test-explorer.md). O motor CLI (`dext test --coverage`) está **Stable**.

---

## Execução via Linha de Comando

Uso: `MeuProjetoTestes.exe [parâmetros]`

| Parâmetro | Alias | Descrição |
| :--- | :--- | :--- |
| `-verbose` | `-v` | Saída detalhada no console |
| `-log` | | Cria um arquivo de log UTF-8 (`.log`) |
| `-dashboard`| `-d` | Inicia o Dashboard Web local (Dext.Sidecar) |
| `-testinsight`| `-x` | Habilita a comunicação com o TestInsight |

### Dext CLI

```bash
dext test
dext test --coverage
dext test --html --output RelatorioTestes.html
```

---

[← Tempo Real](../07-tempo-real/README.md) | [Próximo: Mocking →](mocking.md)
