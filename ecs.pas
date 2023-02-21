unit ecs;

{$IFDEF FPC}
{$mode Delphi}{$H+}
{$ENDIF}

interface

uses Generics.Collections, SysUtils;

const
  NO_ENTITY = UInt64(-1);

type
  TEntityID = UInt64;

  TECSWorld = class;

  { TECSEntity }

  TECSEntity = record
    World: TECSWorld;
    Id: TEntityID;
{$IFNDEF FPC}
    function Get<T>: T;
{$ENDIF}
    function TryGet<T>(out comp: T): Boolean;
    function GetPtr<T>: Pointer;
    function Has<T>: Boolean;
    procedure Add<T>(item: T);
    procedure Update<T>(item: T);
    procedure AddOrUpdate<T>(item: T);
    procedure Remove<T>;
    procedure RemoveAll;
    function ToString: string;
  end;

  TGenericECSStorage = class
  protected type
    TStorageEntityEnumerator = class
      Parent: TGenericECSStorage;
      Index: Integer;
    private
      function GetCurrent: TECSEntity;
    public
      function MoveNext: Boolean;
      property Current: TECSEntity read GetCurrent;
      constructor Create(aParent: TGenericECSStorage);
    end;

  var
    DenseUsed: Integer;
    World: TECSWorld;
    Dense: array of TEntityID;
    Sparse: TDictionary<TEntityID, Integer>;
    CacheIndex: Integer;
    CacheID: TEntityID;
    procedure vRemoveIfExists(Id: TEntityID); virtual; abstract;
    class function ComponentName: string;
    function TryFindIndex(Id: TEntityID; out i: Integer): Boolean;
    function FindIndex(Id: TEntityID): Integer;
    function GetEnumerator: TStorageEntityEnumerator;
    function Has(Id: TEntityID): Boolean;
    procedure Clear;
  end;

  { TECSStorage }

  TECSStorage<T> = class(TGenericECSStorage)
  protected
    Payload: array of T;
    constructor Create(aWorld: TECSWorld);
    procedure vRemoveIfExists(Id: TEntityID); override;
    procedure AddDontCheck(Id: TEntityID; item: T);
    // public
{$IFNDEF FPC}
    function Get(Id: TEntityID): T;
{$ENDIF}
    function TryGet(Id: TEntityID; out comp: T): Boolean;
    function GetPtr(Id: TEntityID): Pointer;
    procedure Update(Id: TEntityID; item: T);
    procedure AddOrUpdate(Id: TEntityID; item: T);
    procedure Add(Id: TEntityID; item: T);
    procedure Remove(Id: TEntityID);
  public
    destructor Destroy; override;
  end;

  // TECSFilter = class;
  TStorageClass = class of TGenericECSStorage;

  TEmptyRecord = record
  end;

  { TWorld }

  TECSFilter = class;

  TECSWorld = class
  protected
    CurId: TEntityID;
    Storages: TDictionary<TStorageClass, TGenericECSStorage>;
    CountComponents: TDictionary<TEntityID, Integer>;
    function GetStorage<T>: TECSStorage<T>;
    function Count<T>: Integer;

  type
    TWorldEntityEnumerator = class
      World: TECSWorld;
      Inner: TEnumerator<TEntityID>;
    private
      function GetCurrent: TECSEntity;
    public
      function MoveNext: Boolean;
      destructor Destroy; override;
      property Current: TECSEntity read GetCurrent;
      constructor Create(aWorld: TECSWorld);
    end;

    TStorageWrapper = class
    private
      Storage: TGenericECSStorage;
    protected
      constructor Create(aStorage: TGenericECSStorage);
    public
      function GetEnumerator: TGenericECSStorage.TStorageEntityEnumerator;
    end;

  public
    function Filter: TECSFilter;
    function NewEntity: TECSEntity;
    constructor Create;
    destructor Destroy; override;
    procedure Clear;
    function GetEnumerator: TWorldEntityEnumerator;
    function Query<T>: TStorageWrapper;
  end;

  TECSFilter = class
  protected
    Included: array of TGenericECSStorage;
    Excluded: array of TGenericECSStorage;
    // optional
    World: TECSWorld;

  type
    TFilterEntityEnumerator = class
      Filter: TECSFilter;
      Inner: TGenericECSStorage.TStorageEntityEnumerator;
    private
      function GetCurrent: TECSEntity;
    public
      function MoveNext: Boolean;
      destructor Destroy; override;
      property Current: TECSEntity read GetCurrent;
      constructor Create(aFilter: TECSFilter;
        aInner: TGenericECSStorage.TStorageEntityEnumerator);
    end;

  function SatisfiedExcept(Entity: TECSEntity;
    ExceptStore: TGenericECSStorage): Boolean;
  public
    function Include<T>: TECSFilter;
    function Exclude<T>: TECSFilter;
    // /// /    procedure Either<T1, T2>;overload;
    // /// /    procedure Either<T1, T2, T3>;overload;
    function GetEnumerator: TFilterEntityEnumerator;
    function Satisfied(Entity: TECSEntity): Boolean;
    constructor Create(aWorld: TECSWorld);
    destructor Destroy; override;
  end;

  TECSSystem = class
  private
    FWorld: TECSWorld;
  public
    property World: TECSWorld read FWorld;
    constructor Create(AOwner: TECSWorld); virtual;
    procedure Init; virtual;
    function Filter: TECSFilter; virtual;
    procedure Execute; virtual;
    procedure Process(e: TECSEntity); virtual;
    procedure Teardown; virtual;
  end;

  TECSSystemClass = class of TECSSystem;

  TECSSystems = class(TECSSystem)
  private type
    TState = (Created, Initialized, TearedDown);

  var
    State: TState;
    Items: array of TECSSystem;
    Filters: array of TECSFilter;
  public
    constructor Create(AOwner: TECSWorld); override;
    procedure Init; override;
    procedure Execute; override;
    procedure Teardown; override;
    function Add(sys: TECSSystem): TECSSystems; overload;
    function Add(sys: TECSSystemClass): TECSSystems; overload;
    destructor Destroy; override;
  end;

const
  NOTHING: TEmptyRecord = ();

implementation

{ TECSStorage }

procedure TGenericECSStorage.Clear;
begin
  DenseUsed := 0;
  Sparse.Clear;
  CacheIndex := -1;
  CacheID := NO_ENTITY;
end;

constructor TECSStorage<T>.Create(aWorld: TECSWorld);
begin
  World := aWorld;
  SetLength(Dense, 1);
  SetLength(Payload, 1);
  Sparse := TDictionary<TEntityID, Integer>.Create;
  CacheIndex := -1;
  CacheID := NO_ENTITY;
end;

destructor TECSStorage<T>.Destroy;
begin
  Sparse.Free;
  inherited Destroy;
end;

function TGenericECSStorage.FindIndex(Id: TEntityID): Integer;
begin
  if Id = CacheID then
    Result := CacheIndex
  else
  begin
    Result := Sparse[Id];
    CacheIndex := Result;
    CacheID := Id;
  end;
end;

{$IFNDEF FPC}

function TECSStorage<T>.Get(Id: TEntityID): T;
begin
  Result := Payload[FindIndex(Id)]
end;
{$ENDIF}

function TGenericECSStorage.GetEnumerator: TStorageEntityEnumerator;
begin
  Result := TStorageEntityEnumerator.Create(Self);
end;

function TGenericECSStorage.TryFindIndex(Id: TEntityID; out i: Integer)
  : Boolean;
begin
  if Id = CacheID then
  begin
    Result := True;
    i := CacheIndex;
    exit;
  end;
  Result := Sparse.TryGetValue(Id, i);
  if Result then
  begin
    CacheIndex := i;
    CacheID := Id;
  end;
end;

function TECSStorage<T>.TryGet(Id: TEntityID; out comp: T): Boolean;
var
  i: Integer;
begin
  Result := TryFindIndex(Id, i);
  if Result then
    comp := Payload[i];
end;

function TECSStorage<T>.GetPtr(Id: TEntityID): Pointer;
begin
  Result := @(Payload[FindIndex(Id)])
end;

function TGenericECSStorage.Has(Id: TEntityID): Boolean;
var
  i: Integer;
begin
  Result := TryFindIndex(Id, i)
end;

procedure TECSStorage<T>.Add(Id: TEntityID; item: T);
var
  i: Integer;
  ent: TECSEntity;
begin
  if TryFindIndex(Id, i) then
  begin
    ent.World := World;
    ent.Id := Id;
    raise Exception.Create('Component ' + ComponentName + ' already added to ' +
      ent.ToString)
  end
  else
    AddDontCheck(Id, item)
end;

procedure TECSStorage<T>.AddDontCheck(Id: TEntityID; item: T);
begin
  if DenseUsed >= length(Dense) then
  begin
    SetLength(Dense, length(Dense) * 2);
    SetLength(Payload, length(Payload) * 2);
  end;
  inc(DenseUsed);
  Payload[DenseUsed - 1] := item;
  Dense[DenseUsed - 1] := Id;
  Sparse.Add(Id, DenseUsed - 1);
  CacheIndex := DenseUsed - 1;
  CacheID := Id;
  if World.CountComponents.ContainsKey(Id) then
    World.CountComponents[Id] := World.CountComponents[Id] + 1
  else
    World.CountComponents.Add(Id, 1);
end;

procedure TECSStorage<T>.Update(Id: TEntityID; item: T);
begin
  Payload[FindIndex(Id)] := item;
end;

procedure TECSStorage<T>.AddOrUpdate(Id: TEntityID; item: T);
var
  i: Integer;
begin
  if TryFindIndex(Id, i) then
    Payload[i] := item
  else
    AddDontCheck(Id, item)
end;

procedure TECSStorage<T>.Remove(Id: TEntityID);
var
  Count, i: Integer;

begin
  i := FindIndex(Id);
  if i <> DenseUsed - 1 then
  begin
    Payload[i] := Payload[DenseUsed - 1];
    Dense[i] := Dense[DenseUsed - 1];
    Sparse[Dense[i]] := i;
  end;
  dec(DenseUsed);
  Sparse.Remove(Id);
  CacheIndex := -1;
  CacheID := NO_ENTITY;
  Count := World.CountComponents[Id];
  if Count = 1 then
    World.CountComponents.Remove(Id)
  else
    World.CountComponents[Id] := Count - 1;
end;

procedure TECSStorage<T>.vRemoveIfExists(Id: TEntityID);
begin
  if Has(Id) then
    Remove(Id)
end;

{ TEntity }

procedure TECSEntity.AddOrUpdate<T>(item: T);
begin
  World.GetStorage<T>.AddOrUpdate(Id, item);
end;

{$IFNDEF FPC}

function TECSEntity.Get<T>: T;
begin
  Result := World.GetStorage<T>.Get(Id);
end;
{$ENDIF}

function TECSEntity.TryGet<T>(out comp: T): Boolean;
begin
  Result := World.GetStorage<T>.TryGet(Id, comp);
end;

function TECSEntity.GetPtr<T>: Pointer;
begin
  Result := World.GetStorage<T>.GetPtr(Id);
end;

function TECSEntity.Has<T>: Boolean;
begin
  Result := World.GetStorage<T>.Has(Id);
end;

procedure TECSEntity.Add<T>(item: T);
begin
  World.GetStorage<T>.Add(Id, item);
end;

procedure TECSEntity.Update<T>(item: T);
begin
  World.GetStorage<T>.Update(Id, item);
end;

procedure TECSEntity.Remove<T>;
begin
  World.GetStorage<T>.Remove(Id);
end;

procedure TECSEntity.RemoveAll;
var
  store: TGenericECSStorage;
begin
  for store in World.Storages.Values do
    store.vRemoveIfExists(Id);
  World.CountComponents.Remove(Id)
end;

function TECSEntity.ToString: string;
var
  store: TGenericECSStorage;
begin
  if Id = NO_ENTITY then
    Result := 'Incorrect entity'
  else
  begin
    Result := Format('Entity(%d): [', [Id]);
    for store in World.Storages.Values do
      if store.Has(Id) then
        Result := Result + store.ComponentName + ',';
    if Result[length(Result)] = ',' then
      Result[length(Result)] := ']'
    else
      Result := Result + ']'
  end;
end;

{ TWorld }

function TECSWorld.GetEnumerator: TWorldEntityEnumerator;
begin
  Result := TWorldEntityEnumerator.Create(Self);
end;

function TECSWorld.GetStorage<T>: TECSStorage<T>;
var
  store: TGenericECSStorage;
begin
  if not Storages.TryGetValue(TECSStorage<T>, store) then
  begin
    store := TECSStorage<T>.Create(Self);
    Storages.Add(TECSStorage<T>, store);
  end;
  Result := TECSStorage<T>(store);
end;

function TECSWorld.NewEntity: TECSEntity;
begin
  Result.World := Self;
  Result.Id := CurId;
  inc(CurId);
  if CurId = NO_ENTITY then
    CurId := 0;
  CountComponents.Add(Result.Id, 0);
end;

function TECSWorld.Query<T>: TStorageWrapper;
begin
  Result := TStorageWrapper.Create(GetStorage<T>);
end;

procedure TECSWorld.Clear;
var
  store: TGenericECSStorage;
begin
  for store in Storages.Values do
    store.Clear;
  CountComponents.Clear;
end;

function TECSWorld.Count<T>: Integer;
var
  store: TGenericECSStorage;
begin
  if not Storages.TryGetValue(TECSStorage<T>, store) then
    Result := 0
  else
    Result := store.DenseUsed;

end;

constructor TECSWorld.Create;
begin
  Storages := TDictionary<TStorageClass, TGenericECSStorage>.Create();
  CountComponents := TDictionary<TEntityID, Integer>.Create;
end;

destructor TECSWorld.Destroy;
var
  store: TGenericECSStorage;
begin
  for store in Storages.Values do
    store.Free;
  Storages.Free;
  CountComponents.Free;
  inherited Destroy;
end;

function TECSWorld.Filter: TECSFilter;
begin
  Result := TECSFilter.Create(Self)
end;

{ TGenericECSStorage }

class function TGenericECSStorage.ComponentName: string;
var
  i: Integer;
begin
  // make TTT from ...TECSStorage<TTT>
  Result := ClassName;
  i := Pos('TECSStorage<', Result);
  Delete(Result, 1, i + length('TECSStorage<'));
  Delete(Result, length(Result), 1);
end;

{ TECSStorage<T>.TStorageEntityEnumerator }

constructor TGenericECSStorage.TStorageEntityEnumerator.Create
  (aParent: TGenericECSStorage);
begin
  Parent := aParent;
  index := -1;
end;

function TGenericECSStorage.TStorageEntityEnumerator.GetCurrent: TECSEntity;
begin
  Result.World := Parent.World;
  Result.Id := Parent.Dense[index];
  Parent.CacheIndex := index;
  Parent.CacheID := Result.Id;
end;

function TGenericECSStorage.TStorageEntityEnumerator.MoveNext: Boolean;
begin
  inc(Index);
  Result := index < Parent.DenseUsed;
end;

{ TECSWorld.TWorldEntityEnumerator }

constructor TECSWorld.TWorldEntityEnumerator.Create(aWorld: TECSWorld);
begin
  World := aWorld;
  Inner := aWorld.CountComponents.Keys.GetEnumerator;
end;

destructor TECSWorld.TWorldEntityEnumerator.Destroy;
begin
  Inner.Free;
  inherited;
end;

function TECSWorld.TWorldEntityEnumerator.GetCurrent: TECSEntity;
begin
  Result.World := World;
  Result.Id := Inner.Current;
end;

function TECSWorld.TWorldEntityEnumerator.MoveNext: Boolean;
begin
  Result := Inner.MoveNext;
end;

{ TECSFilter }

{ TECSFilter }

constructor TECSFilter.Create(aWorld: TECSWorld);
begin
  World := aWorld;
end;

destructor TECSFilter.Destroy;
begin
  inherited;
end;

function TECSFilter.Exclude<T>: TECSFilter;
var
  check, store: TGenericECSStorage;
begin
  store := World.GetStorage<T>;
  for check in Included do
    if check = store then
      raise Exception.Create('Same type' + (TECSStorage<T>.ComponentName) +
        ' cannot be included and excluded to filter');
  SetLength(Excluded, length(Excluded) + 1);
  Excluded[length(Excluded) - 1] := store;
  Result := Self;
end;

function TECSFilter.GetEnumerator: TFilterEntityEnumerator;
var
  min: Integer;
  store, min_storage: TGenericECSStorage;
begin
  min_storage := nil;
  min := MaxInt;
  for store in Included do
  begin
    if store.DenseUsed < min then
    begin
      min := store.DenseUsed;
      min_storage := store;
    end;
  end;
  if not Assigned(min_storage) then
    raise Exception.Create('Include list for filter cannot be empty');
  Result := TFilterEntityEnumerator.Create(Self, min_storage.GetEnumerator)
end;

function TECSFilter.Include<T>: TECSFilter;
var
  check, store: TGenericECSStorage;
begin
  store := World.GetStorage<T>;
  for check in Excluded do
    if check = store then
      raise Exception.Create('Same type' + (TECSStorage<T>.ComponentName) +
        ' cannot be included and excluded to filter');
  SetLength(Included, length(Included) + 1);
  Included[length(Included) - 1] := store;
  Result := Self;
end;

function TECSFilter.Satisfied(Entity: TECSEntity): Boolean;
var
  store: TGenericECSStorage;
begin
  Result := False;
  // TODO - CountComponents < Included.Count once migrated to sparse-sets
  for store in Included do
  begin
    if not store.Has(Entity.Id) then
      exit;
  end;
  for store in Excluded do
  begin
    if store.Has(Entity.Id) then
      exit;
  end;
  Result := True;
end;

function TECSFilter.SatisfiedExcept(Entity: TECSEntity;
  ExceptStore: TGenericECSStorage): Boolean;
var
  store: TGenericECSStorage;
begin
  Result := False;
  // TODO - CountComponents < Included.Count once migrated to sparse-sets
  for store in Included do
  begin
    if store = ExceptStore then
      continue;
    if not store.Has(Entity.Id) then
      exit;
  end;

  for store in Excluded do
  begin
    if store.Has(Entity.Id) then
      exit;
  end;
  Result := True;
end;

{ TECSFilter.TFilterEntityEnumerator }

constructor TECSFilter.TFilterEntityEnumerator.Create(aFilter: TECSFilter;
  aInner: TGenericECSStorage.TStorageEntityEnumerator);
begin
  Filter := aFilter;
  Inner := aInner;
end;

destructor TECSFilter.TFilterEntityEnumerator.Destroy;
begin
  Inner.Free;
  inherited;
end;

function TECSFilter.TFilterEntityEnumerator.GetCurrent: TECSEntity;
begin
  Result := Inner.GetCurrent
end;

function TECSFilter.TFilterEntityEnumerator.MoveNext: Boolean;
begin
  Result := Inner.MoveNext;
  while Result and not Filter.SatisfiedExcept(Inner.Current, Inner.Parent) do
    Result := Inner.MoveNext;
end;

{ TECSSystem }

constructor TECSSystem.Create(AOwner: TECSWorld);
begin
  FWorld := AOwner;
end;

procedure TECSSystem.Execute;
begin
  // does nothing
end;

function TECSSystem.Filter: TECSFilter;
begin
  Result := nil;
end;

procedure TECSSystem.Init;
begin
  // does nothing
end;

procedure TECSSystem.Process(e: TECSEntity);
begin
  // does nothing
end;

procedure TECSSystem.Teardown;
begin
  // does nothing
end;

{ TECSSystems }

function TECSSystems.Add(sys: TECSSystem): TECSSystems;
begin
  assert(State = Created);
  SetLength(Items, length(Items) + 1);
  Items[length(Items) - 1] := sys;
  Result := Self;
end;

function TECSSystems.Add(sys: TECSSystemClass): TECSSystems;
begin
  Result := Add(sys.Create(World));
end;

constructor TECSSystems.Create(AOwner: TECSWorld);
begin
  inherited;
  State := Created;
end;

destructor TECSSystems.Destroy;
var
  sys: TECSSystem;
begin
  assert(State = TearedDown);
  for sys in Items do
    sys.Free;
  inherited;
end;

procedure TECSSystems.Execute;
var
  sys: TECSSystem;
  flt: TECSFilter;
  ent: TECSEntity;
  i: Integer;
begin
  assert(State = Initialized);
  for i := 0 to length(Items) - 1 do
  begin
    sys := Items[i];
    flt := Filters[i];
    if Assigned(flt) then
      for ent in flt do
        sys.Process(ent);
    sys.Execute;
  end;
end;

procedure TECSSystems.Init;
var
  i: Integer;
  sys: TECSSystem;
begin
  assert(State = Created);
  SetLength(Filters, length(Items));
  for i := 0 to length(Items) - 1 do
  begin
    sys := Items[i];
    sys.Init;
    Filters[i] := sys.Filter
  end;
  State := Initialized;
end;

procedure TECSSystems.Teardown;
var
  sys: TECSSystem;
  flt: TECSFilter;
begin
  assert(State = Initialized);
  for sys in Items do
    sys.Teardown;
  for flt in Filters do
    flt.Free;
  State := TearedDown;
end;

{ TECSWorld.TStorageWrapper }

constructor TECSWorld.TStorageWrapper.Create(aStorage: TGenericECSStorage);
begin
  Storage := aStorage
end;

function TECSWorld.TStorageWrapper.GetEnumerator
  : TGenericECSStorage.TStorageEntityEnumerator;
begin
  Result := Storage.GetEnumerator
end;

end.
