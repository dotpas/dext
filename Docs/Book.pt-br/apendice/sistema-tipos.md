# Referência do Sistema de Tipos

O Dext utiliza um sistema de tipos moderno para garantir compatibilidade entre banco de dados e APIs JSON.

## Mapeamento de Tipos

Quando você define uma propriedade na sua Entidade ou DTO, o Dext faz o mapeamento automático:

| Tipo Pascal | JSON | Banco de Dados |
|-------------|------|----------------|
| `Integer` / `Int64` | `Number` | `INTEGER` / `BIGINT` |
| `string` | `String` | `VARCHAR` / `TEXT` |
| `Double` / `Currency` | `Number` | `FLOAT` / `DECIMAL` |
| `Boolean` | `Boolean` | `BIT` / `BOOLEAN` |
| `TDateTime` | `String (ISO)` | `DATETIME` / `TIMESTAMP` |
| `TDate` / `TTime` | `String (ISO)` | `DATE` / `TIME` |
| `TUUID` (GUID) | `String (UUID)` | `UUID` / `CHAR(36)` |
| `TBytes` | `String (Base64)` | `BLOB` / `BYTEA` |

## Tipos Nativos Dext

### TUUID (Dext.Core.Types)
Suporte nativo para UUIDs modernos (RFC 9562), incluindo **UUID v7** (totalmente ordenável por tempo).

### Nullable<T> (Dext.Core.Types)
Permite que tipos primitivos como `Integer` ou `Boolean` aceitem valores nulos do banco de dados ou requisições JSON.

```pascal
property Age: Nullable<Integer>;
```

> **Atenção:** uma variável **local** `Nullable<T>` não começa necessariamente nula.

O Delphi só zera variáveis locais de records que possuem campos gerenciados
(`string`, interfaces, arrays dinâmicos...). O `Nullable<T>` guarda seu estado
em um `Boolean` simples; então, para `T` = `Integer`, `Int64`, `Double`,
`TDateTime` etc., o record não tem conteúdo gerenciado e a variável local
começa com **o lixo que estava na pilha**. Ela pode indicar `HasValue = True`
com um valor aleatório. `Nullable<string>` é seguro, pois a `string` força a
inicialização.

```pascal
var
  Ean: Nullable<Int64>;   // local: estado indefinido!
begin
  Ean.Clear;              // sempre inicialize explicitamente
  // ou: Ean := Default(Nullable<Int64>);
  if Ean.IsNull then ...
end;
```

- Afeta apenas **variáveis locais**. Campos de classe, variáveis globais e
  objetos no heap (incluindo entidades do ORM) são zerados e são seguros.
- Regra: chame `Clear` (ou atribua `Default(...)`) antes de ler um
  `Nullable<T>` local que não recebeu valor.
- Uma correção no framework (`class operator Initialize`) foi avaliada
  (spec S76) e está **em espera**: tornar o record gerenciado pode quebrar
  código que trata records como bytes (`Move`, `FillChar`, acesso por offset).
  O `Clear` explícito é a regra suportada.

### Smart Properties (Prop<T>)
Usado para definir propriedades de Entidade que permitem construção de queries fluentes e verificação em tempo de compilação.

```pascal
class var Props: record
  Name: Prop<string>;
end;
```

---

[← Tópicos Avançados](../10-avancado/README.md) | [Próximo: Dialetos →](dialetos.md)
