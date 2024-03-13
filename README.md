[![Linux CI](https://github.com/konovod/pasecs/actions/workflows/linux.yml/badge.svg)](https://github.com/konovod/pasecs/actions/workflows/linux.yml)
[![Windows CI](https://github.com/konovod/pasecs/actions/workflows/windows.yml/badge.svg)](https://github.com/konovod/pasecs/actions/workflows/windows.yml) 
[![MacOSX CI](https://github.com/konovod/pasecs/actions/workflows/macosx.yml/badge.svg)](https://github.com/konovod/pasecs/actions/workflows/macosx.yml) 
# PasECS

##### Table of Contents  
* [Introduction](#introduction)
* [Main parts of ecs](#main-parts-of-ecs)
  * [Entity](#entity)
  * [Component](#component)
  * [System](#system)
* [Other classes](#other-classes)
  * [TECSWorld](#ecsworld)
  * [TECSFilter](#ecsfilter)
  * [TECSSystems](#ecssystems)
* [Engine integration](#engine-integration)
* [Other features](#other-features)
  * [Statistics](#statistics)
  * [Iterating without filter](#iterating-without-filter)
  * [Callbacks](#callbacks)
* [Benchmarks](#benchmarks)
* [Plans](#plans)
* [Contributors](#contributors)
## Introduction

This is a ECS library for Delphi/FreePascal.

Supported Delphi version: I've tested it on Delphi 11.2, should work on older versions with generics too. Win32 and Win64 works, Linux should work too, Android is planned.
Supported FPC version: I've tested it on FPC 3.2.2.

The library is a single file `ecs.pas`, add it to your project and then do:
```pascal
type
  // declare components
  // they are just records
  TPosition = record
    x, y: Integer;
    constructor Create(x, y: integer); //not required, just for convenience
  end;

  TVelocity = record
    vx, vy: Integer;
    constructor Create(vx, vy: integer); //not required, just for convenience
  end;

  // declare systems
  TUpdatePositionSystem = class(TECSSystem)
    function Filter: TECSFilter; override;
    procedure Process(e: TECSEntity); override;
  end;

function TUpdatePositionSystem.Filter: TECSFilter;
begin
  Result := world.Filter.Include<TPosition>.Include<TVelocity>;
end;

procedure TUpdatePositionSystem.Process(e: TECSEntity);
var
  pos: ^TPosition;
  speed: TVelocity;
begin
  pos := e.GetPtr<TPosition>;
  speed := e.Get<TVelocity>;
  pos^.x := pos^.x+speed.x;
  pos^.y := pos^.y+speed.y;
  // alternatively, use e.Get<TPosition> and then e.Update<TPosition>(pos)
end;

//now main loop of ECS:
var
  world: TECSWorld;
  ent: TECSEntity;
  systems: TECSSystems;
  i: Integer;
begin
  // create world
  world := TECSWorld.Create;
  // create entities
  for i := 1 to 5 do
    world.NewEntity.Add<TPosition>(TPosition.Create(10, 10));
  for i := 1 to 5 do
  begin
    ent := world.NewEntity;
    ent.Add<TPosition>(TPosition.Create(2, 2));
    ent.Add<TVelocity>(TVelocity.Create(1, 1));
  end

  // create systems
  systems = TECSSystems.Create(world);
  systems.add(UpdatePositionSystem) //you can add a created system or just pass a class

  // run systems
  systems.Init;
  for i := 1 to 5 do
    systems.Execute;
  systems.Teardown;
end.
```

## Main parts of ecs

### Entity
Сontainer for components. Consists from UInt64 and pointer to `World`:
```pascal
TECSEntity = record
    World: TECSWorld;
    id: TEntityID;
    ...
```

```pascal
// Creates new entity in world context. 
// Basically just allocates a new identifier so it's fast.
Entity := World.NewEntity;

// Entity is destroyed when last component removed from it.
Entity.RemoveAll;
```

### Component
Container for user data without / with small logic inside. It is just records (could be any type actually, but records are most useful here) :
```pascal
  TComp1 = record
    x : Integer;
    y : Integer;
    name : String;
  end;
```
Components can be added, requested, removed:
```pascal
comp1.x := 0;
comp1.y := 0;
comp1.name := 'name';
Entity := World.NewEntity;
Entity.Add<TComp1>(comp1);
// Will raise exception if component isn't present
comp1 = Entity.Get<TComp1>;
if Entity.TryGet<TComp2>(comp2) then ... //will return false if component isn't present
Entity.Remove<TComp1>;
```

They can be updated (changed) using several ways:
```pascal
var
  comp1: TComp1;
  pcomp1: ^TComp1;
begin
  Entity := World.NewEntity;
  Entity.Add<TComp1>(TComp1.Create(0, 0, 'name'));

  // Replace Comp1 with another instance of Comp1. 
  // Will raise exception if component isn't present
  entity.Update<TComp1>(TComp1.Create(1, 1, 'name1'));

  entity.AddOrUpdate<TComp1>(TComp1.Create(2, 2, 'name2')); // Adds TComp1 or replace it if already present

  // returns Pointer(Comp1), so you can access it directly
  pcomp1 := Entity.GetPtr<TComp1>;
  pcomp1^.x := 5;
  // important - after deleting, component in a pool would be reused
  // so don't save a pointer if you are not sure that component won't be deleted
```

#### Tags
It is not uncommon in ECS to use a components without data, they are called "tags". As constructing of such entity can be cumbersome in pascal, PasECS provides overload of `Add` and `AddOrUpdate` without params:

```pascal
type
  TFloating = record
  end;
  ...

  ent.Add<TColor>(clBlue); // adds normal component TColor
  ent.Add<TFloating>; //adds tag TFloating to entity
```


### System
Сontainer for logic for processing filtered entities. 
User class can override `Init`, `Execute`, `Teardown`, `Filter` and `Process` (in any combination. Just skip methods you don't need).

```pascal
TUserSystem = class(TECSSystem)
  // property World: TECSWorld  - world that system belongs
  // virtual constructor if you need extra logic in constructor 
  // (creating fields etc).
  // Called when `systems.Add(TUserSystem)` is used
  constructor Create(AOwner: TECSWorld);override; 

  // Will be called once during `TECSSystems.Init` call
  procedure Init; override; 

  // Called once during `TECSSystems.Init`, after `Init` call.
  // If this method present, it should return a filter that will be
  // applied to a world.
  // Example: 
  // Result := World.Filter.Include<SomeComponent>.Exclude<Other>;
  function Filter: TECSFilter; override;

  // Will be called on each `TECSSystems.Execute` call
  procedure Execute; override; 

  // Will be called during `TECSSystems.Execute` call, before `sys.Execute`, once for every entity that match `Filter`
  procedure Process(e: TECSEntity); override;

  // Will be called once during `TECSSystems.Teardown` call
  procedure Teardown; override; 
end;
```

### Other classes

#### TECSWorld
Root level container for all entities / components, is iterated with TECSSystems:
```pascal
World := TECSWorld.Create;

// you can delete all entities
World.Clear;

// you can create entity
Entity := World.NewEntity;

// you can iterate all entities in world
for Entity in World do 
  writeln(Entity.ToString);

// you can create filters
Filter := World.Filter.Include(comp1).Exclude(comp2).Include(comp3);
```

#### TECSFilter
Allows to iterate over entities with specified conditions.
Created by call `World.Filter` or inside a `TECSSystem.Filter`.

Filters that is possible:
  - `Include<TComp1>`: Component of type `Comp1` must be present on entity
  - `Exclude<TComp2>`: Entities that contain TComp2 will be excluded from filter
  
All of them can be called 0, 1, or many times using method chaining. Currently, limitation is that `Include` must be called at least once.

You can iterate filter using usual `for entity in filter do ...`

#### TECSSystems
Group of systems to process `TECSWorld` instance:
```pascal
World := TECSWorld.Create;
Systems = TECSSystems.Create(World);

Systems
  .Add(MySystem1.Create(world, SomeParam))
  .Add(MySystem2) { shortcut for add(MySystem2.new(systems.World)) }
  .Add(MySystem3);

Systems.Init;
repeat
  Systems.Execute;
until ShouldQuit;
Systems.Teardown;
```
You can add Systems to Systems to create hierarchy.

System can be in states: 
  - `Created` - constructor was called, but `Init` wasn't. more systems could be added in this state
  - `Initialized` - `Init` was called, now no more systems can be added, but now `Execute can be called`
  - `TearedDown` - `Teardown` was called, can't do `Execute` anymore.

You can inherit your class from `TECSSystems` to add systems automatically:
```pascal
TSampleSystem = class(TECSSystems)
  constructor Create(AOwner: TECSWorld); override;
end;

constructor TSampleSystem.Create(AOwner: TECSWorld);
begin
  inherited;
  Add(TInitPlayerSystem);
  Add(TKeyReactSystem.Create(aOwner, CONFIG_PRESSED,CONFIG_DOWN));
  Add(TReactPlayerSystem);
  Add(MovePlayerSystem);
  Add(RotatePlayerSystem);
  Add(StopRotatePlayerSystem);
  Add(SyncPositionWithPhysicsSystem);
  Add(DrawDebugSystem);
end;
```
### Engine integration
//TODO

In a folder `bench` there is a tests suite and benchmark, you can see it for some examples. Proper example is planned.
In a folder vcl_example i've added simple example of adding ecs to VCL application.

## Other features
### Statistics
 You can get total number of alive entities using `world.EntitiesCount`
 It is also possible to get statistics of how much components exists in world:
```pascal
var
  w: TECSWorld;
  stats: TECSWorld.TStatsArray;
  stat: TECSWorld.TStatsPair;
begin
...
  stats := w.Stats; //alternatively, you can use `w.Stats(stats)` to avoid allocating array every time
  for stat in stats do
    writeln('  ', stat.Key, ': ', stat.Value);
end;
```

### Iterating without filter
Sometimes you just need to check if some component is present in a world. No need to create a filter for it - just use 

`if world.Exists<SomeComponent> then ...`

 You can also count number of components using 

`world.Count<SomeComponent>`

You can also iterate over single component without creating `TECSFilter` using `world.Query<T>`.
It returns a lightweight enumerable, that can be iterated using 

`for entity in world.Query<TMyComponent> do ...` 

Note that it returns entities, not components. To obtain actual components you can do 

```pascal
for entity in world.Query<TMyComponent> do 
begin
  comp1 := entity.Get<TMyComponent>;
  ...
end;
```

This could be useful when iterating inside `System#process`:
```pascal
  function TFindNearestTarget.Filter(World: TECSWorld);
  begin
    Result := World.Include<Pos>.Include<FindTarget>;
  end

  procedure TFindNearestTarget.Process(Entity: TECSEntity);
  var
    Target, Nearest: TECSEntity;
    OurPos, Range, NearestRange: Double;
  begin
    OurPos := entity.Get<Pos>;
    Nearest := nil;
    NearestRange := Inf;
    // world.Filter.Include<IsATarget> will allocate a Filter
    // so you should create it at constructor and store it somewhere
    // so here is an easier way:
    for Target in world.query<IsATarget> do
    begin
      Range := distance(Target.get<Pos>, pos);
      if Range < NearestRange then
      begin
        Nearest := Target;
        NearestRange := Range;
      end
    end;
    // ...
  end;
```

### Callbacks
 //TODO
 
## Benchmarks
//TODO

## Plans
### Short-term
 - [x] runtime statistics
   - [ ] automatic benchmark in TECSSystems?
 - [x] `for entity in World.Query<T>...`
 - [x] `if World.Exists<T> then...`
 - [x] check correctness when deleting entities during iteration
 - [ ] nonoengine integration example, maybe example with VCL
 - [x] CI with FPC
 - [ ] generations in EntityID
### Mid-term
 - [ ] SingleFrame components
 - [ ] Singleton components
 - [ ] Callbacks on adding\deleting components
 - [ ] Multiple components
 - [ ] Android target (`[weak]` annotations etc)
 - [x] Switch to sparsesets? archetypes?

## Contributors
- [Andrey Konovod](https://github.com/konovod) - creator and maintainer
