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

initialization
  // Make sure metadata gets registered/cached
  TModelBuilder.Instance.Entity<TValidatedEntity>;

end.
