unit uApp;

{$IFDEF FPC}
{$mode Delphi}{$H+}
{$ENDIF}

interface

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

procedure DoTests;
var
  w: TECSWorld;
  e1, e2: TECSEntity;
begin
  w := TECSWorld.Create;
  e1 := w.NewEntity;
  e1.Add<TComp1>(TComp1.Create(1,2));
  e1.Add<TComp2>(TComp2.Create('e1'));

  e2 := w.NewEntity;
  e2.Add<TComp2>(TComp2.Create('e2'));

  assert(e1.Get<TComp2>.s = 'e1');
  assert(e2.Get<TComp2>.s = 'e2');

  e1.Replace<TComp2>(TComp2.Create('abc'));
  assert(e1.Get<TComp2>.s = 'abc');

  e1.remove<TComp2>;
  assert(e2.Get<TComp2>.s = 'e2');

  writeln(e1.ToString);
  writeln(e2.ToString);

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
