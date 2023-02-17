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

  TGenericECSStorage = class
  protected
    procedure vRemoveIfExists(id: TEntityID); virtual; abstract;
    function vHas(id: TEntityID): Boolean; virtual; abstract;
    class function ComponentName: string; // TODO
  end;

  { TECSStorage }

  TECSStorage<T> = class(TGenericECSStorage)
  protected
    dense: array of TEntityID;
    payload: array of T;
    dense_used: Integer;
    sparse: TDictionary<TEntityID, integer>;
  protected
    function TryFindIndex(id: TEntityID; out i: integer): Boolean;
    function FindIndex(id: TEntityID): integer;
    constructor Create;
    procedure vRemoveIfExists(id: TEntityID); override;
    function vHas(id: TEntityID): Boolean; override;
    procedure AddDontCheck(id: TEntityID; item: T);
  public
    function Get(id: TEntityID): T;
    function TryGet(id: TEntityID; out comp: T): Boolean;
    function GetPtr(id: TEntityID): Pointer;
    function Has(id: TEntityID): Boolean;
    procedure Replace(id: TEntityID; item: T);
    procedure AddOrReplace(id: TEntityID; item: T);
    procedure Remove(id: TEntityID);
    destructor Destroy; override;
  end;

  TStorageClass = class of TGenericECSStorage;
  TECSWorld = class;

  { TEntity }

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
  end;

  { TWorld }

  TECSWorld = class
  protected
    cur_id: TEntityID;
    storages: TDictionary<TStorageClass, TGenericECSStorage>;
    function GetStorage<T>: TECSStorage<T>;
  public
    function NewEntity: TECSEntity;
    constructor Create;
    destructor Destroy; override;
  end;

implementation

{ TECSStorage }

constructor TECSStorage<T>.Create;
begin
  SetLength(dense, 1);
  SetLength(payload, 1);
  sparse := TDictionary<TEntityID, integer>.Create;
end;

destructor TECSStorage<T>.Destroy;
begin
  sparse.Free;
  inherited Destroy;
end;

function TECSStorage<T>.FindIndex(id: TEntityID): integer;
begin
  Result := sparse[id]
end;

function TECSStorage<T>.Get(id: TEntityID): T;
begin
  Result := payload[FindIndex(id)]
end;

function TECSStorage<T>.TryFindIndex(id: TEntityID; out i: integer): Boolean;
begin
  Result := sparse.TryGetValue(id, i)
end;

function TECSStorage<T>.TryGet(id: TEntityID; out comp: T): Boolean;
var
  i: integer;
begin
  Result := TryFindIndex(id, i);
  if Result then
    comp := payload[i];
end;

function TECSStorage<T>.GetPtr(id: TEntityID): Pointer;
begin
  Result := @(payload[FindIndex(id)])
end;

function TECSStorage<T>.Has(id: TEntityID): Boolean;
var
  i: integer;
begin
  Result := TryFindIndex(id, i)
end;

procedure TECSStorage<T>.AddDontCheck(id: TEntityID; item: T);
begin
  if dense_used >= length(dense) then
  begin
    SetLength(dense, Length(dense)*2);
    SetLength(payload, Length(payload)*2);
  end;
  inc(dense_used);
  payload[dense_used-1] := item;
  dense[dense_used-1] := id;
  sparse.Add(id, dense_used-1)
end;

procedure TECSStorage<T>.Replace(id: TEntityID; item: T);
var
  i: integer;
begin
  payload[FindIndex(id)] := item;
end;

procedure TECSStorage<T>.AddOrReplace(id: TEntityID; item: T);
var
  i: integer;
begin
  if TryFindIndex(id, i) then
    payload[i] := item
  else
    AddDontCheck(id, item)
end;

procedure TECSStorage<T>.Remove(id: TEntityID);
var
  i: integer;
begin
  i := FindIndex(id);
  payload[i] := payload[dense_used-1];
  dense[i] := dense[dense_used-1];
  sparse[dense[i]] := i;
  dec(dense_used);
  sparse.Remove(id);
end;

function TECSStorage<T>.vHas(id: TEntityID): Boolean;
begin
  Result := Has(id);
end;

procedure TECSStorage<T>.vRemoveIfExists(id: TEntityID);
begin
  if Has(id) then
    Remove(id)
end;

{ TEntity }

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
    store.vRemoveIfExists(id)
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
      if store.vHas(id) then
        Result := Result + store.ComponentName + ',';
    if Result[length(Result)] = ',' then
      Result[length(Result)] := ']'
    else
      Result := Result + ']'
  end;
end;

{ TWorld }

function TECSWorld.GetStorage<T>: TECSStorage<T>;
var
  store: TGenericECSStorage;
begin
  if not storages.TryGetValue(TECSStorage<T>, store) then
  begin
    store := TECSStorage<T>.Create;
    storages.Add(TECSStorage<T>, store);
  end;
  Result := TECSStorage<T>(store);
end;

function TECSWorld.NewEntity: TECSEntity;
begin
  Result.World := self;
  Result.id := cur_id;
  Inc(cur_id);
  if cur_id = NO_ENTITY then
    cur_id := 0;
end;

constructor TECSWorld.Create;
begin
  storages := TDictionary<TStorageClass, TGenericECSStorage>.Create();
end;

destructor TECSWorld.Destroy;
var
  store: TGenericECSStorage;
begin
  for store in storages.Values do
    store.Free;
  storages.Free;
  inherited Destroy;
end;

{ TGenericECSStorage }

class function TGenericECSStorage.ComponentName: string;
var
  i: integer;
begin
  // make TTT from ...TECSStorage<TTT>
  Result := ClassName;
  i := Pos('TECSStorage<', Result);
  Delete(Result, 1, i+length('TECSStorage<'));
  Delete(Result, length(Result), 1);
end;

end.
