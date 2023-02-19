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
  for I := 1 to 10 do
  begin
    ent := w.NewEntity;
    ent.Add<TComp1>(TComp1.Create(i, 1));
    if i = 5  then
      ent.Remove<TComp1>;
  end;
  i := 0;
  for ent in w do
    inc(i, ent.Get<TComp1>.x);
  MyAssert(i = 1+2+3+4+5+6+7+8+9+10 - 5);
  w.Free;
end;

procedure TestWorldIterationWithDeletion;
var
  w: TECSWorld;
  ent: TECSEntity;
  i: integer;
begin
  w := TECSWorld.Create;
  for I := 1 to 10 do
  begin
    ent := w.NewEntity;
    ent.Add<TComp1>(TComp1.Create(i, 1));
  end;
  for ent in w do
    if ent.Get<TComp1>.x mod 2 = 0  then
      ent.RemoveAll;
  i := 0;
  for ent in w do
    inc(i, ent.Get<TComp1>.x);

  MyAssert(i = 1+3+5+7+9);
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
    if cycle in [7,8] then
      continue;
    w.Clear;
    for I := 1 to 10 do
    begin
      ent := w.NewEntity;
      ent.Add<TComp1>(TComp1.Create(i, 1));
    end;
    for ent in w do
      if ent.Get<TComp1>.x in [7,8]  then
        ent.RemoveAll
      else if ent.Get<TComp1>.x = Cycle then
        w.NewEntity.Add<TComp1>(TComp1.Create(7+8, 1));
    i := 0;
    for ent in w do
      inc(i, ent.Get<TComp1>.x);
    MyAssert(i = 1+2+3+4+5+6+7+8+9+10);
  end;

  w.Free;
end;

procedure TestSet;
var
  aset: TSet<Integer>;
begin
  aset := TSet<Integer>.Create;
  MyAssert(aset.Contains(123) = false);
  MyAssert(aset.Contains(124) = false);
  aset.Add(123);
  MyAssert(aset.Contains(123) = true);
  MyAssert(aset.Contains(124) = false);
  aset.Add(124);
  MyAssert(aset.Contains(123) = true);
  MyAssert(aset.Contains(124) = true);
  aset.Remove(123);
  MyAssert(aset.Contains(123) = false);
  MyAssert(aset.Contains(124) = true);
  aset.Remove(124);
  MyAssert(aset.Contains(123) = false);
  MyAssert(aset.Contains(124) = false);
  aset.Free;
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

end.
