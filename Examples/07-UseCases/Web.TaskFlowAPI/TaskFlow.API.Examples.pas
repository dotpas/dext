unit TaskFlow.API.Examples;

interface

procedure RunQuickTests;
procedure RegisterExampleData;

implementation

uses
  System.SysUtils,
  TaskFlow.Repository.Interfaces,
  TaskFlow.Repository.Mock,
  TaskFlow.Domain;

procedure RunQuickTests;
var
  Filter: TTaskFilter;
  Status: TTaskStatus;
  Priority: TTaskPriority;
  Repo: ITaskRepository;
  Stats: TTaskStats;
begin
  WriteLn('🧪 RUNNING QUICK TESTS...');

  // Teste 1: Domain Models
  Filter := TTaskFilter.CreateDefault;
  WriteLn('✅ TTaskFilter created: Page=', Filter.Page, ', PageSize=', Filter.PageSize);

  // Teste 2: Enum Helpers
  Status := TTaskStatus.tsInProgress;
  WriteLn('✅ TTaskStatus: ', Status.ToString, ' -> ', Status.ToDisplayText);

  // Teste 3: Priority with color
  Priority := TTaskPriority.tpCritical;
  WriteLn('✅ TTaskPriority: ', Priority.ToString, ' -> ', Priority.ToDisplayText, ' (', Priority.ToColor, ')');

  // Teste 4: Repository
  Repo := TTaskRepositoryMock.Create;
  WriteLn('✅ Repository created with ', Repo.GetTaskCount, ' sample tasks');

  // Teste 5: Stats
  Stats := Repo.GetTasksStats;
  WriteLn('✅ Stats: Total=', Stats.TotalTasks, ', Completed=', Stats.CompletedCount, ', Completion Rate=', Stats.GetCompletionRate:0:1, '%');

  WriteLn('');
  WriteLn('🎉 ALL BASIC TESTS PASSED!');
  WriteLn('');
end;

procedure RegisterExampleData;
var
  Repo: ITaskRepository;
  Task: TTask;
begin
  // Criar repositório e adicionar dados de exemplo adicionais
  Repo := TTaskRepositoryMock.Create as ITaskRepository;

  // Dados de exemplo para demonstrar todas as features
  Repo.CreateTask(TTask.CreateQuick('Revisar código do PR #123', tpHigh));
  Repo.CreateTask(TTask.CreateCritical('Hotfix - Corrigir falha de segurança', 'Urgente: vulnerabilidade XSS identificada'));
  Repo.CreateTask(TTask.CreateWithDueDate('Planejar sprint Q2', Now + 30));
  Repo.CreateTask(TTask.Create('Atualizar documentação', 'Atualizar README e exemplos', tpLow, Now + 14));
  Repo.CreateTask(TTask.Create('Configurar CI/CD', 'Implementar pipeline no GitHub Actions', tpMedium, Now + 7));

  // Marcar algumas como completas para demonstrar estatísticas
  Task := Repo.GetById(6); // Assumindo que este é um ID existente
  Task.Status := tsCompleted;
  Repo.UpdateTask(Task.Id, Task);
end;

end.
