unit uTests;

{$IFDEF FPC}
{$mode Delphi}{$H+}
{$ENDIF}

interface

uses SysUtils;

procedure DoTests;

implementation

uses ecs;

type
  TComp1 = record
    x, y: integer;
    constructor Create(x, y: integer);
  end;

  TComp2 = record
    s: string;
    constructor Create(s: string);
  end;

  TComp3 = record
    class function It: TComp3; static;
  end;

procedure MyAssert(value: boolean);
begin
  if value then
    write('.')
  else
    raise Exception.Create('Test failed');
end;

procedure SimpleTests;
var
  w: TECSWorld;
  e1, e2: TECSEntity;
begin
  w := TECSWorld.Create;
  e1 := w.NewEntity;
  e1.Add<TComp1>(TComp1.Create(1, 2));
  e1.Add<TComp2>(TComp2.Create('e1'));

  e2 := w.NewEntity;
  e2.Add<TComp2>(TComp2.Create('e2'));

  MyAssert(e1.Get<TComp2>.s = 'e1');
  MyAssert(e2.Get<TComp2>.s = 'e2');

  e1.Replace<TComp2>(TComp2.Create('abc'));
  MyAssert(e1.Get<TComp2>.s = 'abc');

  e1.remove<TComp2>;
  MyAssert(e2.Get<TComp2>.s = 'e2');
  w.Free;
end;

procedure TestAddingComponents;
var
  w: TECSWorld;
  ent: TECSEntity;
  c1: TComp1;
  c2: TComp2;
begin
  w := TECSWorld.Create;
  ent := w.NewEntity;
  ent.Add<TComp1>(TComp1.Create(1, 1));
  MyAssert(ent.Get<TComp1>.x = 1);
  MyAssert(ent.Has<TComp1> = true);
  MyAssert(ent.TryGet<TComp1>(c1) = true);
  MyAssert(c1.x = 1);
  MyAssert(ent.Has<TComp2> = false);
  MyAssert(ent.TryGet<TComp2>(c2) = false);
  ent.Add<TComp2>(TComp2.Create('test'));
  MyAssert(ent.Has<TComp2> = true);
  MyAssert(ent.TryGet<TComp2>(c2) = true);
  MyAssert(c2.s = 'test');
  MyAssert(ent.Get<TComp1>.x = 1);
  MyAssert(ent.Get<TComp2>.s = 'test');
  w.Free;
end;

procedure TestAddAndDelete;
var
  w: TECSWorld;
  ent: TECSEntity;
  i: integer;
  c2: TComp2;
begin
  w := TECSWorld.Create;
  ent := w.NewEntity;
  ent.Add<TComp1>(TComp1.Create(1, 1));
  c2 := TComp2.Create('test');
  for i := 1 to 10 do
  begin
    ent.Add<TComp2>(c2);
    ent.remove<TComp2>;
  end;
  MyAssert(c2.s = 'test');
  w.Free;
end;

procedure TestWorldIteration;
var
  w: TECSWorld;
  ent: TECSEntity;
  i: integer;
begin
  w := TECSWorld.Create;
  for i := 1 to 10 do
  begin
    ent := w.NewEntity;
    ent.Add<TComp1>(TComp1.Create(i, 1));
    if i = 5 then
      ent.remove<TComp1>;
  end;
  i := 0;
  for ent in w do
    inc(i, ent.Get<TComp1>.x);
  MyAssert(i = 1 + 2 + 3 + 4 + 5 + 6 + 7 + 8 + 9 + 10 - 5);
  w.Free;
end;

procedure TestWorldIterationWithDeletion;
var
  w: TECSWorld;
  ent: TECSEntity;
  i: integer;
begin
  w := TECSWorld.Create;
  for i := 1 to 10 do
  begin
    ent := w.NewEntity;
    ent.Add<TComp1>(TComp1.Create(i, 1));
  end;
  for ent in w do
    if ent.Get<TComp1>.x mod 2 = 0 then
      ent.RemoveAll;
  i := 0;
  for ent in w do
    inc(i, ent.Get<TComp1>.x);

  MyAssert(i = 1 + 3 + 5 + 7 + 9);
  w.Free;
end;

procedure TestWorldIterationWithAdditionDeletion;
var
  w: TECSWorld;
  ent: TECSEntity;
  cycle, i: integer;
begin
  w := TECSWorld.Create;
  for cycle := 1 to 10 do
  begin
    if cycle in [7, 8] then
      continue;
    w.Clear;
    for i := 1 to 10 do
    begin
      ent := w.NewEntity;
      ent.Add<TComp1>(TComp1.Create(i, 1));
    end;
    for ent in w do
      if ent.Get<TComp1>.x in [7, 8] then
        ent.RemoveAll
      else if ent.Get<TComp1>.x = cycle then
        w.NewEntity.Add<TComp1>(TComp1.Create(7 + 8, 1));
    i := 0;
    for ent in w do
      inc(i, ent.Get<TComp1>.x);
    MyAssert(i = 1 + 2 + 3 + 4 + 5 + 6 + 7 + 8 + 9 + 10);
  end;

  w.Free;
end;

procedure TestSet;
var
  aset: TSet<integer>;
  sum, i: integer;
begin
  aset := TSet<integer>.Create;
  MyAssert(aset.Contains(123) = false);
  MyAssert(aset.Contains(124) = false);
  aset.Add(123);
  MyAssert(aset.Contains(123) = true);
  MyAssert(aset.Contains(124) = false);
  aset.Add(124);

  sum := 0;
  for i in aset do
    inc(sum, i);
  MyAssert(sum = 123 + 124);

  MyAssert(aset.Contains(123) = true);
  MyAssert(aset.Contains(124) = true);
  aset.remove(123);
  MyAssert(aset.Contains(123) = false);
  MyAssert(aset.Contains(124) = true);
  aset.remove(124);
  MyAssert(aset.Contains(123) = false);
  MyAssert(aset.Contains(124) = false);

  sum := 0;
  for i in aset do
    inc(sum, i);
  MyAssert(sum = 0);

  aset.Free;
end;

function SumItems(f: TECSFilter): integer;
var
  ent: TECSEntity;
begin
  Result := 0;
  for ent in f do
    Result := Result + ent.Get<TComp1>.x
end;

procedure TestFilters;
var
  f: TECSFilter;
  w: TECSWorld;
  i: integer;
  ent: TECSEntity;
begin
  w := TECSWorld.Create;
  for i := 1 to 10 do
  begin
    ent := w.NewEntity;
    ent.Add<TComp1>(TComp1.Create(i, 1));
    if i mod 3 = 0 then
      ent.Add<TComp2>(TComp2.Create('test'));
    if i in [5, 6] then
      ent.Add<TComp3>(TComp3.It)
  end;
  f := w.Filter.Include<TComp2>;
  MyAssert(SumItems(f) = 3 + 6 + 9);
  MyAssert(SumItems(f) = 3 + 6 + 9);
  f.Free;
  f := w.Filter.Include<TComp1>.Include<TComp2>;
  MyAssert(SumItems(f) = 3 + 6 + 9);
  f.Free;
  f := w.Filter.Include<TComp2>.Include<TComp1>;
  MyAssert(SumItems(f) = 3 + 6 + 9);
  f.Free;
  f := w.Filter.Include<TComp2>.Exclude<TComp3>;
  MyAssert(SumItems(f) = 3 + 9);
  f.Free;
  f := w.Filter.Include<TComp3>.Include<TComp2>.Exclude<TComp1>;
  MyAssert(SumItems(f) = 0);
  f.Free;

  w.Free;
end;

type
  TTestSystem = class(TECSSystem)
    InitCalled, ExecuteCalled, TeardownCalled: integer;
    procedure Init; override;
    procedure Teardown; override;
    procedure Execute; override;
    function Filter: TECSFilter; override;
    procedure Process(e: TECSEntity); override;
  end;

procedure TestSystems;
var
  w: TECSWorld;
  ent: TECSEntity;
  systems: TECSSystems;
  test: TTestSystem;
begin
  w := TECSWorld.Create;
  systems := TECSSystems.Create(w);
  test := TTestSystem.Create(w);
  systems.Add(test);
  systems.Add(TTestSystem);
  systems.Add(TECSSystem);
  MyAssert(test.InitCalled = 0);
  systems.Init;
  MyAssert(test.InitCalled = 1);

  ent := w.NewEntity;
  ent.Add<TComp1>(TComp1.Create(1, 10));

  MyAssert(test.ExecuteCalled = 0);
  systems.Execute;
  MyAssert(test.ExecuteCalled = 1);

  MyAssert(ent.Get<TComp1>.x = 1 + 10 + 10);

  MyAssert(test.TeardownCalled = 0);
  systems.Teardown;
  MyAssert(test.TeardownCalled = 1);
  systems.Free;
  w.Free;
end;

procedure DoTests;
begin
  writeln('Starting tests suite:');
  SimpleTests;
  TestAddingComponents;
  TestAddAndDelete;
  TestWorldIteration;
  TestWorldIterationWithDeletion;
  TestWorldIterationWithAdditionDeletion;
  TestSet;
  TestFilters;
  TestSystems;
  writeln;
  writeln('Tests passed');
end;

{ TComp1 }

constructor TComp1.Create(x, y: integer);
begin
  Self.x := x;
  Self.y := y;
end;

{ TComp2 }

constructor TComp2.Create(s: string);
begin
  Self.s := s
end;

{ TComp3 }

class function TComp3.It: TComp3;
begin

end;

{ TTestSystem }

procedure TTestSystem.Execute;
begin
  inc(ExecuteCalled)
end;

function TTestSystem.Filter: TECSFilter;
begin
  Result := World.Filter.Include<TComp1>;
end;

procedure TTestSystem.Init;
begin
  inc(InitCalled);
end;

procedure TTestSystem.Process(e: TECSEntity);
var
  ptr: ^TComp1;
begin
  ptr := e.GetPtr<TComp1>;
  ptr.x := ptr.x + ptr.y;
end;

procedure TTestSystem.Teardown;
begin
  inc(TeardownCalled)
end;

end.
