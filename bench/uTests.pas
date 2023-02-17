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

procedure DoTests;
begin
  writeln('Starting tests suite:');
  SimpleTests;
  TestAddingComponents;
  TestAddAndDelete;

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
