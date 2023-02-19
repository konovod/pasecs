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

  TECSEntity = object
  protected
    World: TECSWorld;
    id: TEntityID;
  public
    function Get<T>: T;
    function TryGet<T>(out comp: T): Boolean;
    function GetPtr<T>: Pointer;
    function Has<T>: Boolean;
    procedure Add<T>(item: T);
    procedure Replace<T>(item: T);
    procedure Remove<T>;
    procedure RemoveAll;
    function ToString: string;
    constructor Create(aWorld: TECSWorld; aid: TEntityID);
  end;


  TGenericECSStorage = class
  protected
  type
    TStorageEntityEnumerator = class
      parent : TGenericECSStorage;
      index : Integer;
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
    function Get(id: TEntityID): T;
    function TryGet(id: TEntityID; out comp: T): Boolean;
    function GetPtr(id: TEntityID): Pointer;
    procedure Replace(id: TEntityID; item: T);
    procedure AddOrReplace(id: TEntityID; item: T);
    procedure Remove(id: TEntityID);
  public
    destructor Destroy; override;
  end;

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
  end;


  { TWorld }

  TECSWorld = class
  protected
    cur_id: TEntityID;
    storages: TDictionary<TStorageClass, TGenericECSStorage>;
    CountComponents: TDictionary<TEntityID, Integer>;
    function GetStorage<T>: TECSStorage<T>;
    function Count<T>: Integer;
  type
    TWorldEntityEnumerator = class
      world: TECSWorld;
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
    function NewEntity: TECSEntity;
    constructor Create;
    destructor Destroy; override;
    procedure Clear;
    function GetEnumerator: TWorldEntityEnumerator;
  end;

const
  NOTHING : TEmptyRecord = ();


implementation

{ TECSStorage }

procedure TGenericECSStorage.Clear;
begin
  dense_used := 0;
  sparse.Clear;
end;

constructor TECSStorage<T>.Create(aWorld: TECSWorld);
begin
  World := aWorld;
  SetLength(dense, 1);
  SetLength(payload, 1);
  sparse := TDictionary<TEntityID, Integer>.Create;
end;

destructor TECSStorage<T>.Destroy;
begin
  sparse.Free;
  inherited Destroy;
end;

function TGenericECSStorage.FindIndex(id: TEntityID): Integer;
begin
  Result := sparse[id]
end;

function TECSStorage<T>.Get(id: TEntityID): T;
begin
  Result := payload[FindIndex(id)]
end;

function TGenericECSStorage.GetEnumerator: TStorageEntityEnumerator;
begin
  Result := TStorageEntityEnumerator.Create(Self);
end;

function TGenericECSStorage.TryFindIndex(id: TEntityID; out i: Integer): Boolean;
begin
  Result := sparse.TryGetValue(id, i)
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
  if World.CountComponents.ContainsKey(id) then
    World.CountComponents[id] := World.CountComponents[id]+1
  else
    World.CountComponents.Add(id, 1);
end;

procedure TECSStorage<T>.Replace(id: TEntityID; item: T);
begin
  payload[FindIndex(id)] := item;
end;

procedure TECSStorage<T>.AddOrReplace(id: TEntityID; item: T);
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
  count, i: Integer;

begin
  i := FindIndex(id);
  if i <> dense_used-1 then
  begin
    payload[i] := payload[dense_used - 1];
    dense[i] := dense[dense_used - 1];
    sparse[dense[i]] := i;
  end;
  dec(dense_used);
  sparse.Remove(id);
  count := World.CountComponents[id];
  if count = 1 then
    World.CountComponents.Remove(id)
  else
    World.CountComponents[id] := count-1;
end;

procedure TECSStorage<T>.vRemoveIfExists(id: TEntityID);
begin
  if Has(id) then
    Remove(id)
end;

{ TEntity }

constructor TECSEntity.Create(aWorld: TECSWorld; aid: TEntityID);
begin
  Self.World := aWorld;
  Self.id := aid;
end;

function TECSEntity.Get<T>: T;
begin
  Result := World.GetStorage<T>.Get(id);
end;

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
  World.GetStorage<T>.AddOrReplace(id, item);
end;

procedure TECSEntity.Replace<T>(item: T);
begin
  World.GetStorage<T>.Replace(id, item);
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
  Result.World := self;
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

constructor TGenericECSStorage.TStorageEntityEnumerator.Create(aParent: TGenericECSStorage);
begin
  parent := aParent;
  index := -1;
end;

function TGenericECSStorage.TStorageEntityEnumerator.GetCurrent: TECSEntity;
begin
  Result.World := Parent.World;
  Result.id := parent.dense[index];
end;

function TGenericECSStorage.TStorageEntityEnumerator.MoveNext: Boolean;
begin
 inc(Index);
 Result := index < Parent.dense_used;
end;

{ TECSWorld.TWorldEntityEnumerator }

constructor TECSWorld.TWorldEntityEnumerator.Create(aWorld: TECSWorld);
begin
  world := aWorld;
  inner := aWorld.CountComponents.Keys.GetEnumerator;
end;

destructor TECSWorld.TWorldEntityEnumerator.Destroy;
begin
  inner.Free;
  inherited;
end;

function TECSWorld.TWorldEntityEnumerator.GetCurrent: TECSEntity;
begin
  Result.World := world;
  Result.id := inner.Current;
end;

function TECSWorld.TWorldEntityEnumerator.MoveNext: Boolean;
begin
  Result := inner.MoveNext;
end;


{ TSet<T> }

procedure TSet<T>.Add(x: T);
begin
  Data.Add(x, NOTHING);
end;

function TSet<T>.Contains(x: T): Boolean;
begin
 Result := Data.ContainsKey(x);
end;

constructor TSet<T>.Create;
begin
  Data := TDictionary<T, TEmptyRecord>.Create;
end;

destructor TSet<T>.Destroy;
begin
  Data.Free;
  inherited;
end;

procedure TSet<T>.Remove(x: T);
begin
  Data.Remove(x)
end;

end.
