unit Dext.Entity.Validation.Tests;

interface

uses
  Dext.Testing.Attributes,
  Dext.Assertions,
  Dext.Entity.Context,
  Dext.Entity.Validator,
  Dext.Validation,
  Dext.Entity.Attributes,
  Dext.Entity,
  Dext.Entity.Core,
  System.SysUtils;

type
  [Table('ValidatedEntities')]
  TValidatedEntity = class
  private
    FId: Integer;
    FName: string;
    FEmail: string;
  public
    [PK]
    property Id: Integer read FId write FId;
    [Required]
    property Name: string read FName write FName;
    property Email: string read FEmail write FEmail;
  end;

  TValidatedEntityValidator = class(TAbstractValidator<TValidatedEntity>, IValidator<TValidatedEntity>)
  public
    constructor Create; override;
  end;

  [TestFixture]
  TEntityValidationTests = class
  public
    [Test]
    [Description('Verify Auto-Validation on SaveChanges using attributes fallback')]
    procedure TestAttributeValidationFallback;

    [Test]
    [Description('Verify Auto-Validation on SaveChanges using rich DI Fluent Validator')]
    procedure TestFluentValidatorIntegration;

    [Test]
    [Description('Verify the DI validator adds to the mapping rules instead of replacing them')]
    procedure TestFluentValidatorKeepsMappingRules;

    [Test]
    [Description('PersistAdd and PersistAddRange call the validator registered in DI')]
    procedure TestPersistAddUsesTheRegisteredValidator;

    [Test]
    [Description('PersistUpdate and PersistUpdateRange call the validator registered in DI')]
    procedure TestPersistUpdateUsesTheRegisteredValidator;
  end;

implementation

uses
  Dext.DI.Core,
  Dext.DI.Interfaces;

{ TValidatedEntityValidator }

constructor TValidatedEntityValidator.Create;
begin
  inherited Create;
  RuleFor('Email').EmailAddress;
end;

{ TEntityValidationTests }

procedure TEntityValidationTests.TestAttributeValidationFallback;
var
  Options: TDbContextOptions;
  Ctx: TDbContext;
  Entity: TValidatedEntity;
begin
  Options := TDbContextOptions.Create;
  try
    Options.UseSQLite(':memory:');
    Ctx := TDbContext.Create(Options, nil);
    try
      Ctx.ModelBuilder.Entity<TValidatedEntity>();
      Ctx.EnsureCreated;

      Entity := TValidatedEntity.Create;
      Entity.Id := 1;
      Entity.Name := ''; // Required property empty, should fail
      Entity.Email := 'valid@example.com';
      Ctx.Entities<TValidatedEntity>.Add(Entity);

      // Verify that SaveChanges triggers TEntityValidator and throws EValidationException
      Assert.WillRaise(procedure
        begin
          Ctx.SaveChanges;
        end, EValidationException);
    finally
      Ctx.Free;
    end;
  finally
    Options.Free;
  end;
end;

procedure TEntityValidationTests.TestFluentValidatorIntegration;
var
  Options: TDbContextOptions;
  Ctx: TDbContext;
  Entity: TValidatedEntity;
  Services: IServiceCollection;
  Provider: IServiceProvider;
  OldDefaultProvider: IServiceProvider;
begin
  // Set up DI
  Services := TDextDIFactory.CreateServiceCollection;
  Services.AddSingleton(TServiceType.FromInterface(TypeInfo(IValidator<TValidatedEntity>)), TValidatedEntityValidator);
  Provider := Services.BuildServiceProvider;
  
  OldDefaultProvider := TDextServices.DefaultProvider;
  TDextServices.DefaultProvider := Provider;
  try
    Options := TDbContextOptions.Create;
    try
      Options.UseSQLite(':memory:');
      Ctx := TDbContext.Create(Options, nil);
      try
        Ctx.ModelBuilder.Entity<TValidatedEntity>();
        Ctx.EnsureCreated;

        Entity := TValidatedEntity.Create;
        Entity.Id := 2;
        Entity.Name := 'John Doe';
        Entity.Email := 'invalid-email-address'; // Fluent validator rule will reject this
        Ctx.Entities<TValidatedEntity>.Add(Entity);

        // Verify that SaveChanges triggers TValidatedEntityValidator and throws EValidationException
        Assert.WillRaise(procedure
          begin
            Ctx.SaveChanges;
          end, EValidationException);
      finally
        Ctx.Free;
      end;
    finally
      Options.Free;
    end;
  finally
    TDextServices.DefaultProvider := OldDefaultProvider;
  end;
end;

procedure TEntityValidationTests.TestFluentValidatorKeepsMappingRules;
var
  Options: TDbContextOptions;
  Ctx: TDbContext;
  Entity: TValidatedEntity;
  Services: IServiceCollection;
  Provider: IServiceProvider;
  OldDefaultProvider: IServiceProvider;
begin
  Services := TDextDIFactory.CreateServiceCollection;
  Services.AddSingleton(TServiceType.FromInterface(TypeInfo(IValidator<TValidatedEntity>)), TValidatedEntityValidator);
  Provider := Services.BuildServiceProvider;

  OldDefaultProvider := TDextServices.DefaultProvider;
  TDextServices.DefaultProvider := Provider;
  try
    Options := TDbContextOptions.Create;
    try
      Options.UseSQLite(':memory:');
      Ctx := TDbContext.Create(Options, nil);
      try
        Ctx.ModelBuilder.Entity<TValidatedEntity>();
        Ctx.EnsureCreated;

        Entity := TValidatedEntity.Create;
        Entity.Id := 3;
        Entity.Name := ''; // [Required] in the mapping; the fluent validator does not check it
        Entity.Email := 'valid@example.com';
        Ctx.Entities<TValidatedEntity>.Add(Entity);

        Assert.WillRaise(procedure
          begin
            Ctx.SaveChanges;
          end, EValidationException);
      finally
        Ctx.Free;
      end;
    finally
      Options.Free;
    end;
  finally
    TDextServices.DefaultProvider := OldDefaultProvider;
  end;
end;

procedure WithFluentValidator(const ABody: TProc<TDbContext>);
var
  Options: TDbContextOptions;
  Ctx: TDbContext;
  Services: IServiceCollection;
  OldDefaultProvider: IServiceProvider;
begin
  Services := TDextDIFactory.CreateServiceCollection;
  Services.AddSingleton(TServiceType.FromInterface(TypeInfo(IValidator<TValidatedEntity>)), TValidatedEntityValidator);
  OldDefaultProvider := TDextServices.DefaultProvider;
  TDextServices.DefaultProvider := Services.BuildServiceProvider;
  try
    Options := TDbContextOptions.Create;
    try
      Options.UseSQLite(':memory:');
      Ctx := TDbContext.Create(Options, nil);
      try
        Ctx.ModelBuilder.Entity<TValidatedEntity>();
        Ctx.EnsureCreated;
        ABody(Ctx);
      finally
        Ctx.Free;
      end;
    finally
      Options.Free;
    end;
  finally
    TDextServices.DefaultProvider := OldDefaultProvider;
  end;
end;

function BadEmail(const AId: Integer): TValidatedEntity;
begin
  Result := TValidatedEntity.Create;
  Result.Id := AId;
  Result.Name := 'John Doe';
  Result.Email := 'invalid-email-address'; // only the DI validator rejects this
end;

procedure TEntityValidationTests.TestPersistAddUsesTheRegisteredValidator;
begin
  WithFluentValidator(
    procedure(Ctx: TDbContext)
    begin
      Assert.WillRaise(procedure
        begin
          (Ctx.Entities<TValidatedEntity> as IDbSet).PersistAdd(BadEmail(10));
        end, EValidationException);
      Assert.WillRaise(procedure
        begin
          (Ctx.Entities<TValidatedEntity> as IDbSet).PersistAddRange(
            TArray<TObject>.Create(BadEmail(11)));
        end, EValidationException);
      Should(Ctx.Connection.CreateCommand(
        'SELECT COUNT(*) FROM ValidatedEntities').ExecuteScalar.AsInteger).Be(0);
    end);
end;

procedure TEntityValidationTests.TestPersistUpdateUsesTheRegisteredValidator;
begin
  WithFluentValidator(
    procedure(Ctx: TDbContext)
    var
      Good: TValidatedEntity;
    begin
      Good := TValidatedEntity.Create;
      Good.Id := 20;
      Good.Name := 'John Doe';
      Good.Email := 'john@example.com';
      Ctx.Entities<TValidatedEntity>.Add(Good);
      Ctx.SaveChanges;

      Assert.WillRaise(procedure
        begin
          (Ctx.Entities<TValidatedEntity> as IDbSet).PersistUpdate(BadEmail(20));
        end, EValidationException);
      Assert.WillRaise(procedure
        begin
          (Ctx.Entities<TValidatedEntity> as IDbSet).PersistUpdateRange(
            TArray<TObject>.Create(BadEmail(20)));
        end, EValidationException);
      Should(Ctx.Connection.CreateCommand(
        'SELECT COUNT(*) FROM ValidatedEntities WHERE Email = ''john@example.com''')
        .ExecuteScalar.AsInteger).Be(1);
    end);
end;

initialization
  // Make sure metadata gets registered/cached
  TModelBuilder.Instance.Entity<TValidatedEntity>;

end.
