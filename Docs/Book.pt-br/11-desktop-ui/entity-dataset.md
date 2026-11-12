# Entity DataSet

O **`TEntityDataSet`** é um Dataset em memória de alto desempenho projetado para conectar suas **Listas de Entidades do Dext ORM** diretamente aos componentes visuais tradicionais do Delphi (`TDataSource`, `TDBGrid`, `TDBEdit`) e ferramentas de relatório (como `FastReport` ou `ReportBuilder`).

Em vez de replicar todo o espaço de memória de cada objeto, o **`TEntityDataSet`** usa offsets de memória via os mapas `TEntityMap` do Dext, proporcionando extrema velocidade e zero-allocation.

---

## 🚀 Carregando Dados

Você pode preencher o dataset usando um array de objetos genéricos ou de domínio, ou carregar diretamente de um buffer **JSON ByteSpan** na memória.

### Carregando de uma Lista de Objetos

```pascal
var
  Users: TArray<TUser>;
begin
  Users := Context.Users.ToList; // Busca do Context
  
  DataSet.Load(Users, TUser); // Smart binding
  DataSource.DataSet := DataSet;
end;
```

### Lista Viva ou Cópia

`Load(IObjectList, TClass)` trabalha sobre a **lista viva**: o que o dataset acrescenta ou apaga aparece na lista do chamador. `Load<T>(IList<T>)` copia as referências para uma lista própria: editar um campo muda o mesmo objeto, mas o que entra ou sai fica só no dataset. `LoadFromJson` cria as entidades e é dono delas.

### Carregando diretamente de um Buffer Utf8 JSON

```pascal
var
  JsonBytes: TBytes;
  Span: TByteSpan;
begin
  JsonBytes := TEncoding.UTF8.GetBytes(Payload);
  Span := TByteSpan.Create(JsonBytes);

  DataSet.LoadFromUtf8Json(Span, TUser);
end;
```

---

## 🔍 Filtros e Buscas

O dataset gerencia a ordenação e filtragem puramente em memória usando o framework de queries eficientes do Dext.

### Filtragem por Expressão

Você pode setar filtros nativamente usando tokens clássicos de String:

```pascal
DataSet.Filter := 'Score > 100';
DataSet.Filtered := True;
```

A expressão aceita comparações como `=` e `>`, `AND`, `OR`, `NOT (...)`, `IN (...)` e `LIKE` com `%`. Um filtro que não pode ser lido levanta `EFilterSyntaxError`; nunca é ignorado em silêncio. `IndexFieldNames` ordena a visão (`'Limite DESC'`, `'Cidade;Nome'`) sem tocar na lista de origem.

### Buscas Rápidas (Lookup)

```pascal
if DataSet.Locate('Name', 'Cesar', []) then
  ShowMessage('Encontrado!');
```

---

## 🎨 Experiência em Tempo de Design

O **`TEntityDataSet`** possui integração profunda com a IDE do Delphi. Utilizando o **`TEntityDataProvider`**, ele consegue analisar seu código-fonte e sincronizar metadados sem exigir a compilação total do projeto.

### Verbos do Componente

Clique com o botão direito no componente no Form Designer para acessar estas ferramentas de produtividade:

1.  **Sync Fields (Scan + Update)**: 
    *   Adiciona novos campos encontrados na sua classe de entidade.
    *   Atualiza metadados (DisplayLabel, DisplayFormat, Visibilidade) a partir dos atributos de código.
    *   **Preserva** suas customizações manuais na IDE (Alinhamento, Formatação, etc.) para campos já existentes.
2.  **Refresh Entity (Re-Scan + Rebuild)**: 
    *   Realiza uma limpeza completa.
    *   Deleta todos os campos atuais e os recria estritamente com base nos metadados atuais da Entidade.
    *   Use para um "Hard Reset" ou ao trocar entre entidades totalmente diferentes.

### Estabilização Automática

O Dext garante que o estado de design-time não polua seus arquivos de código:
- **Segurança na Persistência:** A propriedade `Active` é gerenciada automaticamente para que nunca seja salva como `True` no DFM, evitando popups de erro de conexão ao abrir forms.
- **Limpeza Inteligente:** Alterar a propriedade `EntityClassName` dispara automaticamente uma reconstrução total dos campos para evitar contaminação de metadados.

## 💾 Controle de Alterações e Sincronização Remota

O dataset registra nativamente inserções, atualizações e exclusões, facilitando
a sincronização com um servidor REST.

### Semântica de Edição

- `Edit` e `Post` gravam direto na entidade da lista. `Cancel` desfaz a edição em curso, e só ela.
- `Append` cria a entidade no fim do dataset.
- Um dataset somente leitura (`ReadOnly := True`) recusa `Edit`, `Append` e `Delete` com `EDatabaseError`.
- `RejectChanges` desfaz tudo o que está no log: reverte as edições, remove as entidades acrescentadas e devolve as apagadas.

### Log de Alterações Nativo

Quando um registro é editado, inserido ou excluído, o `TEntityDataSet` rastreia
automaticamente na propriedade `Changes`.

```pascal
var
  Change: TEntityChange;
begin
  for Change in DataSet.Changes do
  begin
    case Change.State of
      ersInserted: // Registro novo
      ersModified: // Modificado (lista Change.DirtyFields disponível)
      ersDeleted:  // Tombstone (mapa de chaves primárias em Change.Key)
    end;
  end;
end;
```

Após salvar com sucesso, invoque `AcceptChanges` para consolidar o estado e limpar o log:

```pascal
DataSet.AcceptChanges;
```

### Endpoints REST Auto-Gerados

No servidor, mapeie a entidade para criar os endpoints de sincronização convencionais:

```pascal
App.MapEntityDataSet<TCustomer>('/api/customers', TMyDbContext);
```

Isso registra as seguintes rotas:
- `GET /api/customers` para buscar a lista de registros.
- `POST /api/customers/apply` para persistir o lote de alterações recebido.

O corpo do `apply` é um objeto com um array `changes`. Cada item tem um `state` (`inserted`, `modified` ou `deleted`), uma `key` (em `modified` e `deleted`) e `values` (em `inserted` e `modified`):

```json
{"changes":[
  {"state":"modified","key":{"Id":2},"values":{"Limite":900}},
  {"state":"inserted","values":{"Nome":"Eva","Limite":100}},
  {"state":"deleted","key":{"Id":4}}]}
```

A resposta traz um item por alteração: `Index`, `Success`, `ErrorMessage` e, numa inclusão, as `Keys` geradas. Por padrão o lote é **atômico**: um `SaveChanges`, uma transação, e se um item falha nenhum é aplicado e todos são reportados como falhos (`Batch not applied: ...`). Um armazenamento criado com `ContinueOnError` aplica cada item por si. Um corpo sem `changes` responde 400.

Limite conhecido: dois ou mais deletes do mesmo tipo usam o `DELETE` em lote do contexto, que não confere as linhas afetadas, então uma chave inexistente passa sem erro (um delete sozinho de chave inexistente falha). `TEntityDataSetApi.ListToJson<T>` e `ResultsToJson` escrevem as duas respostas.

Nada no framework monta o corpo do `apply` a partir de `Changes`; o cliente o faz (veja o capítulo do livro sobre o dataset de entidades).

---

## 🏆 Recursos Principais

- **Zero Allocation na Carga de Valores:** A leitura de valores é vinculada a offsets de forma otimizada.
- **DML Memory Mode:** Append, Edit e Delete operacionais dentro da estrutura.
- **Preparado para Component Palette:** Suporte para design-time e sincronização de `TFields` persistentes.

---

## 🛠️ Solução de Problemas

### Conflito de Nomes com o Devart EntityDAC

Se você já possui o **EntityDAC** da Devart instalado na sua IDE do Delphi, pode encontrar um conflito ao tentar instalar o pacote `Dext.EF.Design.bpl`. Ambas as bibliotecas possuem componentes com nomes idênticos (`TEntityDataProvider` e `TEntityDataSet`), e a IDE do Delphi não permite a instalação de componentes diferentes com o mesmo nome.

**Como resolver:**

1. **Você está desenvolvendo uma aplicação Desktop?**
   Se o seu projeto for uma Web API, um Serviço (Daemon) ou uma aplicação Console, você não precisa instalar o pacote visual `Dext.EF.Design.bpl`. Você pode usar o Dext via código normalmente, sem nenhum problema. O pacote de design-time serve apenas para fornecer os componentes visuais para formulários VCL/FMX.

2. **Você pretende usar Devart e Dext no mesmo projeto Desktop?**
   Se a intenção for usar ambos os ORMs visualmente no mesmo projeto, essa limitação da IDE do Delphi impedirá que ambos os pacotes fiquem instalados simultaneamente.

3. **Usando apenas o Dext para sua UI Desktop:**
   Se você deseja usar apenas o Dext, pode desativar temporariamente o pacote da Devart:
   * Na IDE do Delphi, acesse o menu **Component > Install Packages**.
   * Procure os pacotes do Devart EntityDAC na lista e **desmarque-os**.
   * Clique em **Save**.
   * Agora você poderá instalar o pacote `Dext.EF.Design.bpl` e usar os componentes `TEntityDataSet` e `TEntityDataProvider` nos seus forms tranquilamente.

4. **Coexistência via Prefixo (Experimental):**
   Caso precise ter ambas as bibliotecas instaladas simultaneamente (ex: durante uma fase de migração), você pode habilitar o prefixo nos nomes:
   * Abra o arquivo `Sources\Dext.inc`.
   * Descomente `{$DEFINE DEXT_USE_ENTITY_PREFIX}`.
   * Recompile o framework.
   * Os componentes serão registrados como **`TDextEntityDataSet`** e **`TDextEntityDataProvider`**.

