unit ecs_serializer;

interface

uses ecs, Classes, SysUtils, Math, System.Rtti, Generics.Collections;

procedure DumpWorld(w: TECSWorld; s: TStream);
function LoadWorld(s: TStream): TECSWorld;


implementation

uses uSerializationTests, uKBDynamic;

type
TSerializableWorld = class(TECSWorld)
  procedure DumpStorage<T>(s: TStream);
  procedure LoadStorage<T>(s: TStream);
  procedure PatchItem(var x; LContext: TRttiContext; typ: TRTTIType);
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
  ww.DumpStorage<TComponentWithEntitiesArray>(s);
  ww.DumpStorage<TNonExistant>(s);
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
  SetLength(ww.FreeItems,ww.SparseSize);
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
  ww.GetStorage<TComponentWithEntitiesArray>;
  ww.GetStorage<TNonExistant>;

  for var index := 0 to n-1 do
  begin
    var len: Integer;
    s.ReadData(len);
    var str: string;
    SetLength(str, len);
    s.Read(PChar(str)^, len*2);

    var store : TSerializableGenericStorage := nil;
    for var st in ww.Storages.Values do
      if st.ClassName = str then
      begin
        store := TSerializableGenericStorage(st);
        break;
      end;
    if store = nil then
    begin
      raise Exception.Create('not found: '+str);
    end;
    s.ReadData(store.DenseUsed);
    SetLength(store.Dense, Max(store.DenseUsed, 1));
    SetLength(store.Sparse, ww.SparseSize);
    for var i := 0 to store.DenseUsed-1 do
    begin
      s.ReadData(store.Dense[i]);
      store.Sparse[store.Dense[i]] := i;
    end;
  end;

  ww.LoadStorage<TEmptyComponent>(s);
  ww.LoadStorage<TSimpleComponent>(s);
  ww.LoadStorage<TComponentWithString>(s);
  ww.LoadStorage<TComponentWithEntity>(s);
  ww.LoadStorage<TEnumComponent>(s);
  ww.LoadStorage<TComponentWithEntitiesArray>(s);
  ww.LoadStorage<TNonExistant>(s);
end;

{ TSerializableWorld }

procedure TSerializableWorld.DumpStorage<T>(s: TStream);
begin
  var store := TSerializableStorage<T>(GetStorage<T>);
  SetLength(store.Payload, Max(store.DenseUsed, 1));
  TKBDynamic.WriteTo(s, store.Payload, TypeInfo(TArray<T>));
end;

procedure TSerializableWorld.LoadStorage<T>(s: TStream);
var
  LContext: TRttiContext;
begin
  LContext := TRttiContext.Create;
  var store := TSerializableStorage<T>(GetStorage<T>);
  TKBDynamic.ReadFrom(s, store.Payload, TypeInfo(TArray<T>));
  for var i := 0 to store.DenseUsed-1 do
    PatchItem(store.Payload[i], LContext, LContext.GetType(TypeInfo(T)));
  if store.DenseUsed = 0 then
    SetLength(store.Payload, 1);
  LContext.Free;
end;

procedure TSerializableWorld.PatchItem(var x; LContext: TRttiContext; typ: TRTTIType);
begin
//  writeln('!',typ.QualifiedName);
  if typ.ToString = 'TECSEntity' then
    TECSEntity((@x)^).World := self
  else if typ.TypeKind = tkArray then
  begin
    var as_arr := TRttiArrayType(typ);
    if as_arr.ElementType = nil then
      exit;
    var size := as_arr.ElementType.TypeSize;
    for var I := 0 to as_arr.TotalElementCount-1 do
      PatchItem((PByte(@x)+size*i)^, LContext, as_arr.ElementType);
  end
  else if typ.TypeKind = tkRecord then
  begin
    var as_rec := TRttiRecordType(typ);
    for var field in as_rec.GetFields do
      if field.FieldType <> nil then
        PatchItem((PByte(@x)+field.Offset)^, LContext, field.FieldType);
  end;
end;

end.
