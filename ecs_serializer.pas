unit ecs_serializer;

interface

uses ecs, Classes, System.Rtti, Generics.Collections;

procedure DumpWorld(w: TECSWorld; s: TStream);
function LoadWorld(s: TStream): TECSWorld;


implementation

uses uSerializationTests, uKBDynamic;

type
TSerializableWorld = class(TECSWorld)
  procedure DumpStorage<T>(s: TStream);
  procedure LoadStorage<T>(s: TStream);
  procedure PatchItem<T>(var x: T);
end;
TSerializableGenericStorage = class(TGenericECSStorage)
end;
TSerializableStorage<T> = class(TECSStorage<T>)
end;



//https://stackoverflow.com/questions/14742505/how-do-i-instantiate-a-class-from-its-trttitype
//You must cast the TRttiType to the TRttiInstanceType class and then invoke the constructor using the GetMethod function.
//
//Try this sample
//
//var
//  ctx:TRttiContext;
//  lType:TRttiType;
//  t : TRttiInstanceType;
//  f : TValue;
//begin
//  ctx := TRttiContext.Create;
//  lType:= ctx.FindType('UnitName.TFormFormulirPendaftaran');
//  if lType<>nil then
//  begin
//    t:=lType.AsInstance;
//    f:= t.GetMethod('Create').Invoke(t.MetaclassType,[nil]);
//    t.GetMethod('Show').Invoke(f,[]);
//  end;
//end;
//


procedure DumpWorld(w: TECSWorld; s: TStream);
var
  ww: TSerializableWorld;
begin
  ww := TSerializableWorld(w);
  s.WriteData(ww.CurId);
  s.WriteData(ww.SparseSize);
  s.WriteData(ww.NFreeItems);
  for var i := 0 to ww.SparseSize-1 do
    s.WriteData(ww.CountComponents[i]);
  for var i := 0 to ww.NFreeItems-1 do
    s.WriteData(ww.FreeItems[i]);
//    Storages: TDictionary<TStorageClass, TGenericECSStorage>;
  s.WriteData(ww.Storages.Count);
  for var who in ww.Storages.Keys do
  begin
    var store := TSerializableGenericStorage(ww.Storages[who]);

    s.WriteData(length(store.ClassName));
    s.Write(PChar(store.ClassName)^, length(store.ClassName)*2);
    s.WriteData(store.DenseUsed);
    for var i := 0 to ww.SparseSize-1 do
      s.WriteData(store.Sparse[i]);
    for var i := 0 to store.DenseUsed-1 do
      s.WriteData(store.Dense[i]);
    //TODO - well, payloads
  end;

  //HACK
  ww.DumpStorage<TEmptyComponent>(s);
  ww.DumpStorage<TSimpleComponent>(s);
  ww.DumpStorage<TComponentWithString>(s);
  ww.DumpStorage<TComponentWithEntity>(s);
  ww.DumpStorage<TEnumComponent>(s);
end;

function LoadWorld(s: TStream): TECSWorld;
var
  ww: TSerializableWorld;
begin
  Result := TECSWorld.Create;
  ww := TSerializableWorld(Result);
  s.ReadData(ww.CurId);
  s.ReadData(ww.SparseSize);
  s.ReadData(ww.NFreeItems);
  SetLength(ww.CountComponents, ww.SparseSize);
  for var i := 0 to ww.SparseSize-1 do
    s.ReadData(ww.CountComponents[i]);
  SetLength(ww.FreeItems,ww.NFreeItems);
  for var i := 0 to ww.NFreeItems-1 do
    s.readData(ww.FreeItems[i]);
  var n : NativeInt;
  s.ReadData(n);

  //HACK
  ww.GetStorage<TEmptyComponent>;
  ww.GetStorage<TSimpleComponent>;
  ww.GetStorage<TComponentWithString>;
  ww.GetStorage<TComponentWithEntity>;
  ww.GetStorage<TEnumComponent>;

  for var index := 0 to n-1 do
  begin
    var len: Integer;
    s.ReadData(len);
    var str: string;
    SetLength(str, len);
    s.Read(PChar(str)^, len*2);
    writeln(str);

    var store : TSerializableGenericStorage := nil;
    for var st in ww.Storages.Values do
      if st.ClassName = str then
      begin
        store := TSerializableGenericStorage(st);
        break;
      end;
    if store = nil then
    begin
      writeln('not found: '+str);
      readln;
    end;
    s.ReadData(store.DenseUsed);
    SetLength(store.Sparse, ww.SparseSize);
    for var i := 0 to ww.SparseSize-1 do
      s.ReadData(store.Sparse[i]);
    SetLength(store.Dense, store.DenseUsed);
    for var i := 0 to store.DenseUsed-1 do
      s.ReadData(store.Dense[i]);
  end;

  ww.LoadStorage<TEmptyComponent>(s);
  ww.LoadStorage<TSimpleComponent>(s);
  ww.LoadStorage<TComponentWithString>(s);
  ww.LoadStorage<TComponentWithEntity>(s);
  ww.LoadStorage<TEnumComponent>(s);
  writeln('DONE');
end;

{ TSerializableWorld }

procedure TSerializableWorld.DumpStorage<T>(s: TStream);
begin
  var store := TSerializableStorage<T>(GetStorage<T>);
  SetLength(store.Payload, store.DenseUsed);
//  for var x in store.Payload do
//    TKBDynamic.WriteTo(s, x, TypeInfo(T));
  TKBDynamic.WriteTo(s, store.Payload, TypeInfo(TArray<T>));
end;

procedure TSerializableWorld.LoadStorage<T>(s: TStream);
begin
  var store := TSerializableStorage<T>(GetStorage<T>);
  SetLength(store.Payload, store.DenseUsed);
  TKBDynamic.ReadFrom(s, store.Payload, TypeInfo(TArray<T>));
  for var i := 0 to store.DenseUsed-1 do
    PatchItem<T>(store.Payload[i])

end;

procedure TSerializableWorld.PatchItem<T>(var x: T);
var
  LContext: TRttiContext;
begin
  var typ := LContext.GetType(TypeInfo(T));
  if typ.ToString = 'TECSEntity' then
    TECSEntity((@x)^).World := self;
end;

end.
