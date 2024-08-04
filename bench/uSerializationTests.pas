unit uSerializationTests;

interface

uses Classes, ecs, ecs_serializer;

procedure DoSerializationTests;

type
  TEmptyComponent = record
  end;

  TSimpleComponent = record
    x,y: Integer;
  end;

  TComponentWithString = record
    a: Integer;
    b: string;
    c: Double;
    z: array[1..4] of Integer;
  end;

  TComponentWithEntity = record
    n: integer;
    e: TECSEntity;
  end;


  TCrunchArray = array[1..10] of TECSEntity;
  TComponentWithEntitiesArray = record
    n: integer;
    e: TCrunchArray;
  end;

  TEnumComponent = (Value1, Value2, Value3);

  TNonExistant = record
    n: Integer;
  end;

implementation

uses uTests;

procedure DoSerializationTests;
var
  w1, w2: TECSWorld;
  ent: TECSEntity;
  mem: TMemoryStream;
begin
  w1 := TECSWorld.Create;

  var c1: TSimpleComponent;
  c1.x := 10; c1.y := 100;
  var c2: TComponentWithString;
  c2.a := 123; c2.b := 'This is a string'; c2.c := -0.5;
  var c3: TComponentWithEntity;
  c3.n := 1000;

  ent := w1.NewEntity;
  ent.Add<TEmptyComponent>;
  ent.Add(c1);
  c3.e := ent;
  ent := w1.NewEntity;
  ent.Add(Value1);
  ent.Add(c2);
  ent.Add(c3);
  c3.n := 10000;
  c3.e.Id := NO_ENTITY;
  w1.NewEntity.Add(c3);

  var c4: TComponentWithEntitiesArray;
  c4.n := 2;
  c4.e[1] := ent;
  c4.e[2] := w1.NewEntity;
  w1.NewEntity.Add(c4);

  writeln('old: ');
  for var pair in w1.Stats do
    writeln(pair.key, ': ', pair.value);
  writeln('---');

  mem := TMemoryStream.Create;
  DumpWorld(w1, mem);

  writeln(mem.Position);

  var nn: TNonExistant;
  w1.NewEntity.Add(nn);


  w1.Free;

  mem.Position := 0;
  w2 := LoadWorld(mem);
  writeln('new: ');
  for var pair in w2.Stats do
    writeln(pair.key, ': ', pair.value);

  for var e in w2.Query<TComponentWithString> do
    MyAssert(e.Get<TComponentWithString>.b = 'This is a string');
  for var e in w2.Query<TComponentWithEntity> do
    MyAssert(e.Get<TComponentWithEntity>.e.World = w2);
  for var e in w2.Query<TComponentWithEntitiesArray> do
    MyAssert((e.Get<TComponentWithEntitiesArray>.e[1].World = w2) and (e.Get<TComponentWithEntitiesArray>.e[2].World = w2));

  w2.Singleton<TComponentWithEntitiesArray>.Remove<TComponentWithEntitiesArray>;

  var n: TNonExistant;
  w2.NewEntity.Add(n);

  w2.Free;
  mem.Free;
end;





end.
