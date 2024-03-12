unit ecs;

{$IFDEF FPC}
{$mode Delphi}{$H+}
{$ENDIF}
{$Q-}

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
    function Get<T>: T;
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
    TStorageEntityEnumerator = record
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
    Sparse: array of Integer;
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
{$IFNDEF FPC}
    // doesn't work due to [bug](https://gitlab.com/freepascal.org/fpc/source/-/issues/40155)
    function Get(Id: TEntityID): T;
{$ENDIF}
    function TryGet(Id: TEntityID; out comp: T): Boolean;
    function GetPtr(Id: TEntityID): Pointer;
    procedure Update(Id: TEntityID; item: T);
    procedure AddOrUpdate(Id: TEntityID; item: T);
    procedure Add(Id: TEntityID; item: T);
    procedure Remove(Id: TEntityID);
  end;

  TStorageClass = class of TGenericECSStorage;

  TECSFilter = class;

  { TWorld }

  TECSWorld = class
  protected
    CurId: TEntityID;
    Storages: TDictionary<TStorageClass, TGenericECSStorage>;
    CountComponents: array of Integer;
    FreeItems: array of TEntityID;
    NFreeItems: Integer;
    SparseSize: Integer;
    function GetStorage<T>: TECSStorage<T>;
    procedure AddFreeItem(it: TEntityID);
  type
    TWorldEntityEnumerator = record
      World: TECSWorld;
      NextItem: TEntityID;
    private
      function GetCurrent: TECSEntity;
    public
      function MoveNext: Boolean;
      property Current: TECSEntity read GetCurrent;
      constructor Create(aWorld: TECSWorld);
    end;

  public type
    TStorageWrapper = record
      Storage: TGenericECSStorage;
      constructor Create(aStorage: TGenericECSStorage);
      function GetEnumerator: TGenericECSStorage.TStorageEntityEnumerator;
    end;

  function Filter: TECSFilter;
  function NewEntity: TECSEntity;
  constructor Create;
  destructor Destroy; override;
  procedure Clear;
  function GetEnumerator: TWorldEntityEnumerator;
  function Query<T>: TStorageWrapper;
  function Count<T>: Integer;
  function Exists<T>: Boolean;
  end;

  TECSFilter = class
  protected
    Included: array of TGenericECSStorage;
    Excluded: array of TGenericECSStorage;
    // TODO - Optional: array of array of TGenericECSStorage;
    World: TECSWorld;

  type
    TFilterEntityEnumerator = record
      Filter: TECSFilter;
      Inner: TGenericECSStorage.TStorageEntityEnumerator;
    private
      function GetCurrent: TECSEntity;
    public
      function MoveNext: Boolean;
      property Current: TECSEntity read GetCurrent;
      constructor Create(aFilter: TECSFilter;
        aInner: TGenericECSStorage.TStorageEntityEnumerator);
    end;

  function SatisfiedExcept(Entity: TECSEntity;
    ExceptStore: TGenericECSStorage): Boolean;
  public
    function Include<T>: TECSFilter;
    function Exclude<T>: TECSFilter;
    // TODO - procedure Either<T1, T2>;overload;
    // TODO - procedure Either<T1, T2, T3>;overload;
    function GetEnumerator: TFilterEntityEnumerator;
    function Satisfied(Entity: TECSEntity): Boolean;
    constructor Create(aWorld: TECSWorld);
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

implementation

const
  DEFAULT_ENTITY_POOL_SIZE = 1024;

  { TECSStorage }

procedure TGenericECSStorage.Clear;
begin
  DenseUsed := 0;
  CacheIndex := -1;
  CacheID := NO_ENTITY;
end;

constructor TECSStorage<T>.Create(aWorld: TECSWorld);
begin
  World := aWorld;
  SetLength(Dense, 1);
  SetLength(Payload, 1);
  SetLength(Sparse, World.SparseSize);
  CacheIndex := -1;
  CacheID := NO_ENTITY;
end;

function TGenericECSStorage.FindIndex(Id: TEntityID): Integer;
var
  Wrong: TECSEntity;
begin
  if Id = CacheID then
    Result := CacheIndex
  else
  begin
    Result := Sparse[Id];
    if (Result >= DenseUsed) or (Dense[Result] <> Id) then
    begin
      Wrong.World := World;
      Wrong.Id := Id;
      raise Exception.Create('Component '+ComponentName+' not found in '+Wrong.ToString);
    end;
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
  i := Sparse[Id];
  Result := (i < DenseUsed) and (Dense[i] = Id);
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
  Sparse[Id] := DenseUsed - 1;
  CacheIndex := DenseUsed - 1;
  CacheID := Id;
  World.CountComponents[Id] := World.CountComponents[Id] + 1
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
  i: Integer;
begin
  i := FindIndex(Id);
  if i <> DenseUsed - 1 then
  begin
    Payload[i] := Payload[DenseUsed - 1];
    Dense[i] := Dense[DenseUsed - 1];
    Sparse[Dense[i]] := i;
  end;
  dec(DenseUsed);
  CacheIndex := -1;
  CacheID := NO_ENTITY;
  World.CountComponents[Id] := World.CountComponents[Id] - 1;
  if World.CountComponents[Id] = 0 then
    World.AddFreeItem(id);
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

{$IFDEF FPC}
// TStorage<T>.Get doesn't work due to [bug](https://gitlab.com/freepascal.org/fpc/source/-/issues/40155)
// so use GetPtr here
function TECSEntity.Get<T>: T;
begin
  Result := T(World.GetStorage<T>.GetPtr(Id)^);
end;

{$ELSE}

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
var
  store: TGenericECSStorage;
begin
  Result.World := Self;
  if NFreeItems > 0 then
  begin
    Result.Id := FreeItems[NFreeItems-1];
    Dec(NFreeItems);
    exit;
  end;


  Result.Id := CurId;
  inc(CurId);
  // if CurId = NO_ENTITY then
  // CurId := 0;
  if CurId >= SparseSize then
  begin
    SparseSize := SparseSize * 2;
    SetLength(CountComponents, SparseSize);
    SetLength(FreeItems, SparseSize);
    for store in Storages.Values do
      SetLength(store.Sparse, SparseSize);
  end;
//  CountComponents[Result.Id] := 0;
end;

function TECSWorld.Query<T>: TStorageWrapper;
begin
  Result := TStorageWrapper.Create(GetStorage<T>);
end;

procedure TECSWorld.AddFreeItem(it: TEntityID);
begin
  Inc(NFreeItems);
  FreeItems[NFreeItems-1] := it
end;

procedure TECSWorld.Clear;
var
  store: TGenericECSStorage;
begin
  for store in Storages.Values do
    store.Clear;
  SetLength(CountComponents, 0);
  SetLength(CountComponents, SparseSize);
  NFreeItems := 0;
  CurId := 0;
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
  SparseSize := DEFAULT_ENTITY_POOL_SIZE;
  SetLength(CountComponents, SparseSize);
  SetLength(FreeItems, SparseSize)
end;

destructor TECSWorld.Destroy;
var
  store: TGenericECSStorage;
begin
  for store in Storages.Values do
    store.Free;
  Storages.Free;
  inherited Destroy;
end;

function TECSWorld.Exists<T>: Boolean;
begin
  Result := Count<T> > 0
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
  if (index < 0) or (Parent.CacheID = Parent.Dense[index]) then
    inc(Index);
  Result := index < Parent.DenseUsed;
end;

{ TECSWorld.TWorldEntityEnumerator }

constructor TECSWorld.TWorldEntityEnumerator.Create(aWorld: TECSWorld);
begin
  World := aWorld;
  NextItem := 0;
end;

function TECSWorld.TWorldEntityEnumerator.GetCurrent: TECSEntity;
begin
  Result.World := World;
  Result.Id := NextItem-1
end;

function TECSWorld.TWorldEntityEnumerator.MoveNext: Boolean;
begin
  Result := True;
  while NextItem <= World.CurId do
  begin
    inc(NextItem);
    if World.CountComponents[NextItem-1] > 0 then
      exit;
  end;
  Result := False;
end;

{ TECSFilter }

{ TECSFilter }

constructor TECSFilter.Create(aWorld: TECSWorld);
begin
  World := aWorld;
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
  if World.CountComponents[Entity.Id] < Length(Included) then
    exit;
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
  if World.CountComponents[Entity.Id] < Length(Included) then
    exit;
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
