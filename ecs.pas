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
    id: TEntityID;
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
      parent: TGenericECSStorage;
      index: Integer;
    private
      function GetCurrent: TECSEntity;
    public
      function MoveNext: Boolean;
      property Current: TECSEntity read GetCurrent;
      constructor Create(aParent: TGenericECSStorage);
    end;

  var
    dense_used: Integer;
    World: TECSWorld;
    dense: array of TEntityID;
    sparse: TDictionary<TEntityID, Integer>;
    CacheIndex: Integer;
    CacheID: TEntityID;
    procedure vRemoveIfExists(id: TEntityID); virtual; abstract;
    class function ComponentName: string;
    function TryFindIndex(id: TEntityID; out i: Integer): Boolean;
    function FindIndex(id: TEntityID): Integer;
    function GetEnumerator: TStorageEntityEnumerator;
    function Has(id: TEntityID): Boolean;
    procedure Clear;
  end;

  { TECSStorage }

  TECSStorage<T> = class(TGenericECSStorage)
  protected
    payload: array of T;
    constructor Create(aWorld: TECSWorld);
    procedure vRemoveIfExists(id: TEntityID); override;
    procedure AddDontCheck(id: TEntityID; item: T);
    // public
    {$IFNDEF FPC}
    function Get(id: TEntityID): T;
    {$ENDIF}
    function TryGet(id: TEntityID; out comp: T): Boolean;
    function GetPtr(id: TEntityID): Pointer;
    procedure Update(id: TEntityID; item: T);
    procedure AddOrUpdate(id: TEntityID; item: T);
    procedure Add(id: TEntityID; item: T);
    procedure Remove(id: TEntityID);
  public
    destructor Destroy; override;
  end;

  // TECSFilter = class;
  TStorageClass = class of TGenericECSStorage;

  TEmptyRecord = record
  end;

  TSet<T> = class
  private
    data: TDictionary<T, TEmptyRecord>;
  public
    constructor Create;
    destructor Destroy; override;
    procedure Add(x: T);
    procedure Remove(x: T);
    function Contains(x: T): Boolean;
    function GetEnumerator: TEnumerator<T>;
    function Count: Integer;
  end;

  { TWorld }

  TECSFilter = class;

  TECSWorld = class
  protected
    cur_id: TEntityID;
    storages: TDictionary<TStorageClass, TGenericECSStorage>;
    CountComponents: TDictionary<TEntityID, Integer>;
    function GetStorage<T>: TECSStorage<T>;
    function Count<T>: Integer;

  type
    TWorldEntityEnumerator = class
      World: TECSWorld;
      inner: TEnumerator<TEntityID>;
    private
      function GetCurrent: TECSEntity;
    public
      function MoveNext: Boolean;
      destructor Destroy; override;
      property Current: TECSEntity read GetCurrent;
      constructor Create(aWorld: TECSWorld);
    end;

  public
    function Filter: TECSFilter;
    function NewEntity: TECSEntity;
    constructor Create;
    destructor Destroy; override;
    procedure Clear;
    function GetEnumerator: TWorldEntityEnumerator;
  end;

  TECSFilter = class
  protected
    included: TSet<TStorageClass>;
    excluded: TSet<TStorageClass>;
    // optional
    World: TECSWorld;

  type
    TFilterEntityEnumerator = class
      Filter: TECSFilter;
      inner: TGenericECSStorage.TStorageEntityEnumerator;
    private
      function GetCurrent: TECSEntity;
    public
      function MoveNext: Boolean;
      destructor Destroy; override;
      property Current: TECSEntity read GetCurrent;
      constructor Create(aFilter: TECSFilter;
        aInner: TGenericECSStorage.TStorageEntityEnumerator);
    end;
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
  dense_used := 0;
  sparse.Clear;
  CacheIndex := -1;
  CacheID := NO_ENTITY;
end;

constructor TECSStorage<T>.Create(aWorld: TECSWorld);
begin
  World := aWorld;
  SetLength(dense, 1);
  SetLength(payload, 1);
  sparse := TDictionary<TEntityID, Integer>.Create;
  CacheIndex := -1;
  CacheID := NO_ENTITY;
end;

destructor TECSStorage<T>.Destroy;
begin
  sparse.Free;
  inherited Destroy;
end;

function TGenericECSStorage.FindIndex(id: TEntityID): Integer;
begin
  if id = CacheID then
    Result := CacheIndex
  else
  begin
    Result := sparse[id];
    CacheIndex := Result;
    CacheID := id;
  end;
end;

{$IFNDEF FPC}
function TECSStorage<T>.Get(id: TEntityID): T;
begin
  Result := payload[FindIndex(id)]
end;
{$ENDIF}

function TGenericECSStorage.GetEnumerator: TStorageEntityEnumerator;
begin
  Result := TStorageEntityEnumerator.Create(Self);
end;

function TGenericECSStorage.TryFindIndex(id: TEntityID; out i: Integer)
  : Boolean;
begin
  if id = CacheID then
  begin
    Result := True;
    i := CacheIndex;
    exit;
  end;
  Result := sparse.TryGetValue(id, i);
  if Result then
  begin
    CacheIndex := i;
    CacheID := id;
  end;
end;

function TECSStorage<T>.TryGet(id: TEntityID; out comp: T): Boolean;
var
  i: Integer;
begin
  Result := TryFindIndex(id, i);
  if Result then
    comp := payload[i];
end;

function TECSStorage<T>.GetPtr(id: TEntityID): Pointer;
begin
  Result := @(payload[FindIndex(id)])
end;

function TGenericECSStorage.Has(id: TEntityID): Boolean;
var
  i: Integer;
begin
  Result := TryFindIndex(id, i)
end;

procedure TECSStorage<T>.Add(id: TEntityID; item: T);
var
  i: Integer;
  ent: TECSEntity;
begin
  if TryFindIndex(id, i) then
  begin
    ent.World := World;
    ent.id := id;
    raise Exception.Create('Component ' + ComponentName + ' already added to ' +
      ent.ToString)
  end
  else
    AddDontCheck(id, item)
end;

procedure TECSStorage<T>.AddDontCheck(id: TEntityID; item: T);
begin
  if dense_used >= length(dense) then
  begin
    SetLength(dense, length(dense) * 2);
    SetLength(payload, length(payload) * 2);
  end;
  inc(dense_used);
  payload[dense_used - 1] := item;
  dense[dense_used - 1] := id;
  sparse.Add(id, dense_used - 1);
  CacheIndex := dense_used - 1;
  CacheID := id;
  if World.CountComponents.ContainsKey(id) then
    World.CountComponents[id] := World.CountComponents[id] + 1
  else
    World.CountComponents.Add(id, 1);
end;

procedure TECSStorage<T>.Update(id: TEntityID; item: T);
begin
  payload[FindIndex(id)] := item;
end;

procedure TECSStorage<T>.AddOrUpdate(id: TEntityID; item: T);
var
  i: Integer;
begin
  if TryFindIndex(id, i) then
    payload[i] := item
  else
    AddDontCheck(id, item)
end;

procedure TECSStorage<T>.Remove(id: TEntityID);
var
  Count, i: Integer;

begin
  i := FindIndex(id);
  if i <> dense_used - 1 then
  begin
    payload[i] := payload[dense_used - 1];
    dense[i] := dense[dense_used - 1];
    sparse[dense[i]] := i;
  end;
  dec(dense_used);
  sparse.Remove(id);
  CacheIndex := -1;
  CacheID := NO_ENTITY;
  Count := World.CountComponents[id];
  if Count = 1 then
    World.CountComponents.Remove(id)
  else
    World.CountComponents[id] := Count - 1;
end;

procedure TECSStorage<T>.vRemoveIfExists(id: TEntityID);
begin
  if Has(id) then
    Remove(id)
end;

{ TEntity }

procedure TECSEntity.AddOrUpdate<T>(item: T);
begin
  World.GetStorage<T>.AddOrUpdate(id, item);
end;

{$IFNDEF FPC}
function TECSEntity.Get<T>: T;
begin
  Result := World.GetStorage<T>.Get(id);
end;
{$ENDIF}

function TECSEntity.TryGet<T>(out comp: T): Boolean;
begin
  Result := World.GetStorage<T>.TryGet(id, comp);
end;

function TECSEntity.GetPtr<T>: Pointer;
begin
  Result := World.GetStorage<T>.GetPtr(id);
end;

function TECSEntity.Has<T>: Boolean;
begin
  Result := World.GetStorage<T>.Has(id);
end;

procedure TECSEntity.Add<T>(item: T);
begin
  World.GetStorage<T>.Add(id, item);
end;

procedure TECSEntity.Update<T>(item: T);
begin
  World.GetStorage<T>.Update(id, item);
end;

procedure TECSEntity.Remove<T>;
begin
  World.GetStorage<T>.Remove(id);
end;

procedure TECSEntity.RemoveAll;
var
  store: TGenericECSStorage;
begin
  for store in World.storages.Values do
    store.vRemoveIfExists(id);
  World.CountComponents.Remove(id)
end;

function TECSEntity.ToString: string;
var
  store: TGenericECSStorage;
begin
  if id = NO_ENTITY then
    Result := 'Incorrect entity'
  else
  begin
    Result := Format('Entity(%d): [', [id]);
    for store in World.storages.Values do
      if store.Has(id) then
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
  if not storages.TryGetValue(TECSStorage<T>, store) then
  begin
    store := TECSStorage<T>.Create(Self);
    storages.Add(TECSStorage<T>, store);
  end;
  Result := TECSStorage<T>(store);
end;

function TECSWorld.NewEntity: TECSEntity;
begin
  Result.World := Self;
  Result.id := cur_id;
  inc(cur_id);
  if cur_id = NO_ENTITY then
    cur_id := 0;
  CountComponents.Add(Result.id, 0);
end;

procedure TECSWorld.Clear;
var
  store: TGenericECSStorage;
begin
  for store in storages.Values do
    store.Clear;
  CountComponents.Clear;
end;

function TECSWorld.Count<T>: Integer;
var
  store: TGenericECSStorage;
begin
  if not storages.TryGetValue(TECSStorage<T>, store) then
    Result := 0
  else
    Result := store.dense_used;

end;

constructor TECSWorld.Create;
begin
  storages := TDictionary<TStorageClass, TGenericECSStorage>.Create();
  CountComponents := TDictionary<TEntityID, Integer>.Create;
end;

destructor TECSWorld.Destroy;
var
  store: TGenericECSStorage;
begin
  for store in storages.Values do
    store.Free;
  storages.Free;
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
  parent := aParent;
  index := -1;
end;

function TGenericECSStorage.TStorageEntityEnumerator.GetCurrent: TECSEntity;
begin
  Result.World := parent.World;
  Result.id := parent.dense[index];
  parent.CacheIndex := index;
  parent.CacheID := Result.id;
end;

function TGenericECSStorage.TStorageEntityEnumerator.MoveNext: Boolean;
begin
  inc(Index);
  Result := index < parent.dense_used;
end;

{ TECSWorld.TWorldEntityEnumerator }

constructor TECSWorld.TWorldEntityEnumerator.Create(aWorld: TECSWorld);
begin
  World := aWorld;
  inner := aWorld.CountComponents.Keys.GetEnumerator;
end;

destructor TECSWorld.TWorldEntityEnumerator.Destroy;
begin
  inner.Free;
  inherited;
end;

function TECSWorld.TWorldEntityEnumerator.GetCurrent: TECSEntity;
begin
  Result.World := World;
  Result.id := inner.Current;
end;

function TECSWorld.TWorldEntityEnumerator.MoveNext: Boolean;
begin
  Result := inner.MoveNext;
end;

{ TECSFilter }

{ TSet<T> }

procedure TSet<T>.Add(x: T);
begin
  data.Add(x, NOTHING);
end;

function TSet<T>.Contains(x: T): Boolean;
begin
  Result := data.ContainsKey(x);
end;

function TSet<T>.Count: Integer;
begin
  Result := data.Count
end;

constructor TSet<T>.Create;
begin
  data := TDictionary<T, TEmptyRecord>.Create;
end;

destructor TSet<T>.Destroy;
begin
  data.Free;
  inherited;
end;

function TSet<T>.GetEnumerator: TEnumerator<T>;
begin
  Result := data.Keys.GetEnumerator;
end;

procedure TSet<T>.Remove(x: T);
begin
  data.Remove(x)
end;

{ TECSFilter }

constructor TECSFilter.Create(aWorld: TECSWorld);
begin
  World := aWorld;
  included := TSet<TStorageClass>.Create;
  excluded := TSet<TStorageClass>.Create;
end;

destructor TECSFilter.Destroy;
begin
  included.Free;
  excluded.Free;
  inherited;
end;

function TECSFilter.Exclude<T>: TECSFilter;
begin
  if included.Contains(TECSStorage<T>) then
    raise Exception.Create('Same type' + (TECSStorage<T>.ComponentName) +
      ' cannot be included and excluded to filter');
  excluded.Add(TECSStorage<T>);
  Result := Self;
end;

function TECSFilter.GetEnumerator: TFilterEntityEnumerator;
var
  min: Integer;
  typ: TStorageClass;
  store, min_storage: TGenericECSStorage;
begin
  min_storage := nil;
  min := MaxInt;
  for typ in included do
  begin
    if not World.storages.TryGetValue(typ, store) then
    begin
      // TODO - always empty enumerator
      raise Exception.Create('Component ' + typ.ComponentName +
        ' was not added to world, cannot create filter');
    end;
    if store.dense_used < min then
    begin
      min := store.dense_used;
      min_storage := store;
    end;
  end;
  if not Assigned(min_storage) then
    raise Exception.Create('Include list for filter cannot be empty');
  Result := TFilterEntityEnumerator.Create(Self, min_storage.GetEnumerator)
end;

function TECSFilter.Include<T>: TECSFilter;
begin
  if excluded.Contains(TECSStorage<T>) then
    raise Exception.Create('Same type' + (TECSStorage<T>.ComponentName) +
      ' cannot be included and excluded to filter');
  included.Add(TECSStorage<T>);
  Result := Self;
end;

function TECSFilter.Satisfied(Entity: TECSEntity): Boolean;
var
  store: TGenericECSStorage;
  typ: TStorageClass;
  Count: Integer;
begin
  Result := false;
  if not World.CountComponents.TryGetValue(Entity.id, Count) then
    exit;
  if Count < included.Count then
    exit;
  for typ in included do
  begin
    if not World.storages.TryGetValue(typ, store) then
      exit;
    if not store.Has(Entity.id) then
      exit;
  end;
  for typ in excluded do
  begin
    if not World.storages.TryGetValue(typ, store) then
      continue;
    if store.Has(Entity.id) then
      exit;
  end;
  Result := True;
end;

{ TECSFilter.TFilterEntityEnumerator }

constructor TECSFilter.TFilterEntityEnumerator.Create(aFilter: TECSFilter;
  aInner: TGenericECSStorage.TStorageEntityEnumerator);
begin
  Filter := aFilter;
  inner := aInner;
end;

destructor TECSFilter.TFilterEntityEnumerator.Destroy;
begin
  inner.Free;
  inherited;
end;

function TECSFilter.TFilterEntityEnumerator.GetCurrent: TECSEntity;
begin
  Result := inner.GetCurrent
end;

function TECSFilter.TFilterEntityEnumerator.MoveNext: Boolean;
begin
  Result := inner.MoveNext;
  while Result and not Filter.Satisfied(inner.Current) do
    Result := inner.MoveNext;
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

end.
