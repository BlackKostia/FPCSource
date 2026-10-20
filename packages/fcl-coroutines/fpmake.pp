{
    This file is part of the Free Pascal run time library.
    Copyright (c) 2026 by the Free Pascal development team

    fpmake.pp for fcl-coroutines package

    See the file COPYING.FPC, included in this distribution,
    for details about the copyright.
}

{$ifndef ALLPACKAGES}
{$mode objfpc}{$H+}
program fpmake;

uses {$ifdef unix}cthreads,{$endif} fpmkunit;

var
  P: TPackage;
  T: TTarget;
begin
  with Installer do
  begin
{$endif ALLPACKAGES}
    { Fibers, generators and async state machine builders. Kept apart from
      fcl-async (fpAsync), which fcl-net depends on: these units need
      vcl-compat, which itself depends on fcl-net through fcl-web. }
    P := AddPackage('fcl-coroutines');
    P.ShortName := 'fclcor';
{$ifdef ALLPACKAGES}
    P.Directory := ADirectory;
{$endif ALLPACKAGES}
    P.Description := 'Coroutines, fibers, generators and async state machines for Free Pascal';
    P.Version := '3.3.1';
    P.Author := 'Free Pascal development team';
    P.License := 'LGPL with modification';
    P.HomepageURL := 'http://www.freepascal.org/';
    P.NeedLibC := false;
    { Fibers switch stacks with System V AMD64 assembly (async.fiber has a
      $FATAL for other CPUs); the branch targets x86_64-linux only
      (docs/concurrency/adr/0011-target-platform.md). }
    P.OSes := [linux];
    P.CPUs := [x86_64];

    P.Dependencies.Add('rtl-extra');
    P.Dependencies.Add('vcl-compat');
    P.Dependencies.Add('fcl-base');
    P.Dependencies.Add('fcl-eventloop');

    P.SourcePath.Add('src');

    T := P.Targets.AddUnit('async.types.pp');
    T := P.Targets.AddUnit('async.fiber.pp');
      T.Dependencies.AddUnit('async.types');
    T := P.Targets.AddUnit('async.generator.pp');
      T.Dependencies.AddUnit('async.fiber');
    T := P.Targets.AddUnit('async.statemachine.pp');
      T.Dependencies.AddUnit('async.types');
    T := P.Targets.AddUnit('fclasync.pp');
      with T.Dependencies do
        begin
          AddUnit('async.fiber');
          AddUnit('async.generator');
          AddUnit('async.statemachine');
        end;

{$ifndef ALLPACKAGES}
    Run;
  end;
end.
{$endif ALLPACKAGES}
