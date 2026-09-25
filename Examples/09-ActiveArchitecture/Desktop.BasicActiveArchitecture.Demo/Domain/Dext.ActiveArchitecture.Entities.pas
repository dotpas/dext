unit Dext.ActiveArchitecture.Entities;

interface

uses
  Dext.Entity,
  Dext.Entity.Mapping,
  Dext.Core.SmartTypes,
  Dext.Types.Nullable,
  Dext.Types.Lazy,
  Dext.Specifications.Types,
  System.SysUtils,
  System.Classes;

type
  TSuppliers = class;
  TOrders = class;
  TOrderDetails = class;
  TTerritories = class;
  TCustomerDemographics = class;
  TCustomerCustomerDemo = class;
  TCategories = class;
  TProducts = class;
  TEmployeeTerritories = class;
  TCustomers = class;
  TShippers = class;
  TEmployees = class;
  TRegion = class;

  [Table('Orders')]
  TOrders = class
  private
    FOrderId: IntType;
    FCustomerId: StringType;
    FEmployeeId: IntType;
    FOrderDate: DateTimeType;
    FRequiredDate: DateTimeType;
    FShippedDate: DateTimeType;
    FShipVia: IntType;
    FFreight: CurrencyType;
    FShipName: StringType;
    FShipAddress: StringType;
    FShipCity: StringType;
    FShipRegion: StringType;
    FShipPostalCode: StringType;
    FShipCountry: StringType;
    FShipViaNavigation: Lazy<TShippers>;
    FCustomer: Lazy<TCustomers>;
    FEmployee: Lazy<TEmployees>;
  public
    [PK, Column('OrderID'), DisplayLabel('Pedido')]
    property OrderId: IntType read FOrderId write FOrderId;

    [Column('CustomerID'), DisplayLabel('Cliente'), MaxLength(5)]
    property CustomerId: StringType read FCustomerId write FCustomerId;

    [Column('EmployeeID'), DisplayLabel('Usuário')]
    property EmployeeId: IntType read FEmployeeId write FEmployeeId;

    property OrderDate: DateTimeType read FOrderDate write FOrderDate;
    [Visible(False)]
    property RequiredDate: DateTimeType read FRequiredDate write FRequiredDate;
    property ShippedDate: DateTimeType read FShippedDate write FShippedDate;
    property ShipVia: IntType read FShipVia write FShipVia;
    property Freight: CurrencyType read FFreight write FFreight;
    [MaxLength(40)]
    property ShipName: StringType read FShipName write FShipName;
    [MaxLength(60)]
    property ShipAddress: StringType read FShipAddress write FShipAddress;
    [MaxLength(15)]
    property ShipCity: StringType read FShipCity write FShipCity;
    [MaxLength(15)]
    property ShipRegion: StringType read FShipRegion write FShipRegion;
    [MaxLength(10)]
    property ShipPostalCode: StringType read FShipPostalCode write FShipPostalCode;
    [MaxLength(15)]
    property ShipCountry: StringType read FShipCountry write FShipCountry;
    [ForeignKey('ShipVia')]
    property ShipViaNavigation: Lazy<TShippers> read FShipViaNavigation write FShipViaNavigation;
    [ForeignKey('CustomerID')]
    property Customer: Lazy<TCustomers> read FCustomer write FCustomer;
    [ForeignKey('EmployeeID')]
    property Employee: Lazy<TEmployees> read FEmployee write FEmployee;
  end;

  [Table('Order Details')]
  TOrderDetails = class
  private
    FOrderId: IntType;
    FProductId: IntType;
    FUnitPrice: CurrencyType;
    FQuantity: IntType;
    FDiscount: FloatType;
  public
    [PK, Column('OrderID'), DisplayLabel('Pedido')]
    property OrderId: IntType read FOrderId write FOrderId;
    [PK, Column('ProductID'), DisplayLabel('Produto')]
    property ProductId: IntType read FProductId write FProductId;
    [DisplayLabel('Preço Unitário')]
    property UnitPrice: CurrencyType read FUnitPrice write FUnitPrice;
    [DisplayLabel('Quantidade')]
    property Quantity: IntType read FQuantity write FQuantity;
    [DisplayLabel('Desconto')]
    property Discount: FloatType read FDiscount write FDiscount;

    // Regra de Domínio Rico (Desconto Progressivo)
    function CalcularDescontoProgressivo: Double;
    function ObterTotalComDesconto: Double;
  end;

  [Table('Suppliers')]
  TSuppliers = class
  private
    FSupplierId: IntType;
    FCompanyName: StringType;
    FContactName: StringType;
    FContactTitle: StringType;
    FAddress: StringType;
    FCity: StringType;
    FRegion: StringType;
    FPostalCode: StringType;
    FCountry: StringType;
    FPhone: StringType;
    FFax: StringType;
    FHomePage: StringType;
  public
    [PK, Column('SupplierID')]
    property SupplierId: IntType read FSupplierId write FSupplierId;
    [MaxLength(40)]
    property CompanyName: StringType read FCompanyName write FCompanyName;
    [MaxLength(30)]
    property ContactName: StringType read FContactName write FContactName;
    [MaxLength(30)]
    property ContactTitle: StringType read FContactTitle write FContactTitle;
    [MaxLength(60)]
    property Address: StringType read FAddress write FAddress;
    [MaxLength(15)]
    property City: StringType read FCity write FCity;
    [MaxLength(15)]
    property Region: StringType read FRegion write FRegion;
    [MaxLength(10)]
    property PostalCode: StringType read FPostalCode write FPostalCode;
    [MaxLength(15)]
    property Country: StringType read FCountry write FCountry;
    [MaxLength(24)]
    property Phone: StringType read FPhone write FPhone;
    [MaxLength(24)]
    property Fax: StringType read FFax write FFax;
    property HomePage: StringType read FHomePage write FHomePage;
  end;

  [Table('Territories')]
  TTerritories = class
  private
    FTerritoryId: StringType;
    FTerritoryDescription: StringType;
    FRegionId: IntType;
    FRegion: Lazy<TRegion>;
  public
    [PK, MaxLength(20), Column('TerritoryID')]
    property TerritoryId: StringType read FTerritoryId write FTerritoryId;
    [MaxLength(50)]
    property TerritoryDescription: StringType read FTerritoryDescription write FTerritoryDescription;
    [Column('RegionID')]
    property RegionId: IntType read FRegionId write FRegionId;
    [ForeignKey('RegionID')]
    property Region: Lazy<TRegion> read FRegion write FRegion;
  end;

  [Table('CustomerDemographics')]
  TCustomerDemographics = class
  private
    FCustomerTypeId: StringType;
    FCustomerDesc: StringType;
  public
    [PK, MaxLength(10), Column('CustomerTypeID')]
    property CustomerTypeId: StringType read FCustomerTypeId write FCustomerTypeId;
    property CustomerDesc: StringType read FCustomerDesc write FCustomerDesc;
  end;

  [Table('CustomerCustomerDemo')]
  TCustomerCustomerDemo = class
  private
    FCustomerId: StringType;
    FCustomerTypeId: StringType;
    FCustomer: Lazy<TCustomers>;
    FCustomerType: Lazy<TCustomerDemographics>;
  public
    [PK, MaxLength(5), Column('CustomerID')]
    property CustomerId: StringType read FCustomerId write FCustomerId;
    [PK, MaxLength(10), Column('CustomerTypeID')]
    property CustomerTypeId: StringType read FCustomerTypeId write FCustomerTypeId;
    [ForeignKey('CustomerID')]
    property Customer: Lazy<TCustomers> read FCustomer write FCustomer;
    [ForeignKey('CustomerTypeID')]
    property CustomerType: Lazy<TCustomerDemographics> read FCustomerType write FCustomerType;
  end;

  [Table('Categories')]
  TCategories = class
  private
    FCategoryId: IntType;
    FCategoryName: StringType;
    FDescription: StringType;
    FPicture: TBytes;
  public
    [PK, Column('CategoryID')]
    property CategoryId: IntType read FCategoryId write FCategoryId;
    [MaxLength(15)]
    property CategoryName: StringType read FCategoryName write FCategoryName;
    property Description: StringType read FDescription write FDescription;
    property Picture: TBytes read FPicture write FPicture;
  end;

  [Table('Products')]
  TProducts = class
  private
    FProductId: IntType;
    FProductName: StringType;
    FSupplierId: IntType;
    FCategoryId: IntType;
    FQuantityPerUnit: StringType;
    FUnitPrice: CurrencyType;
    FUnitsInStock: IntType;
    FUnitsOnOrder: IntType;
    FReorderLevel: IntType;
    FDiscontinued: BoolType;
    FSupplier: Lazy<TSuppliers>;
    FCategory: Lazy<TCategories>;
  public
    [PK, Column('ProductID')]
    property ProductId: IntType read FProductId write FProductId;
    [MaxLength(40)]
    property ProductName: StringType read FProductName write FProductName;
    [Column('SupplierID')]
    property SupplierId: IntType read FSupplierId write FSupplierId;
    [Column('CategoryID')]
    property CategoryId: IntType read FCategoryId write FCategoryId;
    [MaxLength(20)]
    property QuantityPerUnit: StringType read FQuantityPerUnit write FQuantityPerUnit;
    property UnitPrice: CurrencyType read FUnitPrice write FUnitPrice;
    property UnitsInStock: IntType read FUnitsInStock write FUnitsInStock;
    property UnitsOnOrder: IntType read FUnitsOnOrder write FUnitsOnOrder;
    property ReorderLevel: IntType read FReorderLevel write FReorderLevel;
    property Discontinued: BoolType read FDiscontinued write FDiscontinued;
    [ForeignKey('SupplierID')]
    property Supplier: Lazy<TSuppliers> read FSupplier write FSupplier;
    [ForeignKey('CategoryID')]
    property Category: Lazy<TCategories> read FCategory write FCategory;
  end;

  [Table('EmployeeTerritories')]
  TEmployeeTerritories = class
  private
    FEmployeeId: IntType;
    FTerritoryId: StringType;
    FEmployee: Lazy<TEmployees>;
    FTerritory: Lazy<TTerritories>;
  public
    [PK, Column('EmployeeID')]
    property EmployeeId: IntType read FEmployeeId write FEmployeeId;
    [PK, MaxLength(20), Column('TerritoryID')]
    property TerritoryId: StringType read FTerritoryId write FTerritoryId;
    [ForeignKey('EmployeeID')]
    property Employee: Lazy<TEmployees> read FEmployee write FEmployee;
    [ForeignKey('TerritoryID')]
    property Territory: Lazy<TTerritories> read FTerritory write FTerritory;
  end;

  [Table('Customers')]
  TCustomers = class
  private
    FCustomerId: StringType;
    FCompanyName: StringType;
    FContactName: StringType;
    FContactTitle: StringType;
    FAddress: StringType;
    FCity: StringType;
    FRegion: StringType;
    FPostalCode: StringType;
    FCountry: StringType;
    FPhone: StringType;
    FFax: StringType;
  public
    [PK, MaxLength(5), Column('CustomerID')]
    property CustomerId: StringType read FCustomerId write FCustomerId;
    [MaxLength(40)]
    property CompanyName: StringType read FCompanyName write FCompanyName;
    [MaxLength(30)]
    property ContactName: StringType read FContactName write FContactName;
    [MaxLength(30)]
    property ContactTitle: StringType read FContactTitle write FContactTitle;
    [MaxLength(60)]
    property Address: StringType read FAddress write FAddress;
    [MaxLength(15)]
    property City: StringType read FCity write FCity;
    [MaxLength(15)]
    property Region: StringType read FRegion write FRegion;
    [MaxLength(10)]
    property PostalCode: StringType read FPostalCode write FPostalCode;
    [MaxLength(15)]
    property Country: StringType read FCountry write FCountry;
    [MaxLength(24)]
    property Phone: StringType read FPhone write FPhone;
    [MaxLength(24)]
    property Fax: StringType read FFax write FFax;
  end;

  [Table('Shippers')]
  TShippers = class
  private
    FShipperId: IntType;
    FCompanyName: StringType;
    FPhone: StringType;
  public
    [PK, Column('ShipperID')]
    property ShipperId: IntType read FShipperId write FShipperId;
    [MaxLength(40)]
    property CompanyName: StringType read FCompanyName write FCompanyName;
    [MaxLength(24)]
    property Phone: StringType read FPhone write FPhone;
  end;

  [Table('Employees')]
  TEmployees = class
  private
    FEmployeeId: IntType;
    FLastName: StringType;
    FFirstName: StringType;
    FTitle: StringType;
    FTitleOfCourtesy: StringType;
    FBirthDate: DateTimeType;
    FHireDate: DateTimeType;
    FAddress: StringType;
    FCity: StringType;
    FRegion: StringType;
    FPostalCode: StringType;
    FCountry: StringType;
    FHomePhone: StringType;
    FExtension: StringType;
    FPhoto: TBytes;
    FNotes: StringType;
    FReportsTo: IntType;
    FPhotoPath: StringType;
    FReportsToNavigation: Lazy<TEmployees>;
  public
    [PK, Column('EmployeeID')]
    property EmployeeId: IntType read FEmployeeId write FEmployeeId;
    [MaxLength(20)]
    property LastName: StringType read FLastName write FLastName;
    [MaxLength(10)]
    property FirstName: StringType read FFirstName write FFirstName;
    [MaxLength(30)]
    property Title: StringType read FTitle write FTitle;
    [MaxLength(25)]
    property TitleOfCourtesy: StringType read FTitleOfCourtesy write FTitleOfCourtesy;
    property BirthDate: DateTimeType read FBirthDate write FBirthDate;
    property HireDate: DateTimeType read FHireDate write FHireDate;
    [MaxLength(60)]
    property Address: StringType read FAddress write FAddress;
    [MaxLength(15)]
    property City: StringType read FCity write FCity;
    [MaxLength(15)]
    property Region: StringType read FRegion write FRegion;
    [MaxLength(10)]
    property PostalCode: StringType read FPostalCode write FPostalCode;
    [MaxLength(15)]
    property Country: StringType read FCountry write FCountry;
    [MaxLength(24)]
    property HomePhone: StringType read FHomePhone write FHomePhone;
    [MaxLength(4)]
    property Extension: StringType read FExtension write FExtension;
    property Photo: TBytes read FPhoto write FPhoto;
    property Notes: StringType read FNotes write FNotes;
    property ReportsTo: IntType read FReportsTo write FReportsTo;
    [MaxLength(255)]
    property PhotoPath: StringType read FPhotoPath write FPhotoPath;
    [ForeignKey('ReportsTo')]
    property ReportsToNavigation: Lazy<TEmployees> read FReportsToNavigation write FReportsToNavigation;
  end;

  [Table('Region')]
  TRegion = class
  private
    FRegionId: IntType;
    FRegionDescription: StringType;
  public
    [PK, Column('RegionID')]
    property RegionId: IntType read FRegionId write FRegionId;
    [MaxLength(50)]
    property RegionDescription: StringType read FRegionDescription write FRegionDescription;
  end;

implementation

{ TOrderDetails }

function TOrderDetails.CalcularDescontoProgressivo: Double;
var
  Quantidade: Integer;
begin
  Quantidade := FQuantity;
  if Quantidade <= 10 then
    FDiscount := 0.0
  else if Quantidade <= 50 then
    FDiscount := 0.05
  else
    FDiscount := 0.10;
    
  Result := FDiscount;
end;

function TOrderDetails.ObterTotalComDesconto: Double;
begin
  Result := (FUnitPrice * FQuantity) * (Double(1.0) - FDiscount);
end;

initialization
  TOrders.ClassName;
  TOrderDetails.ClassName;

end.
