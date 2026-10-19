{
    This file is part of the Free Component Library (FCL)
    Copyright (c) 2026 by the Free Pascal development team

    Async State Machine Builders & TaskCompletionSource (Phase 4, Step 1 & 2)
    Provides runtime foundation for stackless async/await state machines

    See the file COPYING.FPC, included in this distribution,
    for details about the copyright.
}
{$mode objfpc}{$H+}
{$modeswitch advancedrecords}
{$modeswitch functionreferences}
{$modeswitch anonymousfunctions}

unit async.statemachine;

interface

uses
  SysUtils, Classes, SyncObjs,
  System.Threading,
  async.types;

type
  { Holds the outcome of a TTaskCompletionSource until its task reads it. }
  TCompletionState = class(TInterfacedObject)
  private
    FError: Exception;
  public
    destructor Destroy; override;
    procedure RaiseStoredError;
  end;

  { Manual Task Completion Source for typed results.

    Task is a future that is not started until SetResult, SetException or
    SetCanceled is called: waiting for it does not occupy a pool thread.
    The task stays valid after the source is freed. Freeing a source that
    was never completed cancels its task, so that nobody waits forever. }
  generic TTaskCompletionSource<TResult> = class
  public type
    TFutureT = specialize IFuture<TResult>;
  private type
    TValueState = class(TCompletionState)
    public
      Value: TResult;
      function Take: TResult;
    end;
  private
    FTask: TFutureT;
    FState: TValueState;
    FStateRef: IInterface;
    FCompleted: LongInt;
    function Claim: Boolean;
  public
    constructor Create;
    destructor Destroy; override;
    function SetResult(const AResult: TResult): Boolean;
    { Takes ownership of AException, also when it returns False. }
    function SetException(const AException: Exception): Boolean;
    function SetCanceled: Boolean;
    property Task: TFutureT read FTask;
  end;

  { State machine method builder for typed futures }
  generic TAsyncTaskMethodBuilder<TResult> = record
  private type
    TSource = specialize TTaskCompletionSource<TResult>;
  private
    FSource: TSource;
    FTask: specialize IFuture<TResult>;
    procedure EnsureSource;
  public
    class function Create: specialize TAsyncTaskMethodBuilder<TResult>; static;
    function GetTask: specialize IFuture<TResult>;
    procedure Start(const AStateMachine: IAsyncStateMachine);
    procedure AwaitOnCompleted(const ATask: ITask; const AStateMachine: IAsyncStateMachine);
    { SetResult and SetException complete the task and free the source. }
    procedure SetResult(const AResult: TResult);
    procedure SetException(const AException: Exception);
    property Task: specialize IFuture<TResult> read GetTask;
  end;

  { State machine method builder for void ITask }
  TAsyncTaskBuilder = record
  private
    FSource: specialize TTaskCompletionSource<Boolean>;
    FTask: ITask;
    procedure EnsureSource;
  public
    class function Create: TAsyncTaskBuilder; static;
    function GetTask: ITask;
    procedure Start(const AStateMachine: IAsyncStateMachine);
    procedure AwaitOnCompleted(const ATask: ITask; const AStateMachine: IAsyncStateMachine);
    procedure SetResult;
    procedure SetException(const AException: Exception);
    property Task: ITask read GetTask;
  end;

implementation

{ TCompletionState }

destructor TCompletionState.Destroy;
begin
  FreeAndNil(FError);
  inherited Destroy;
end;

procedure TCompletionState.RaiseStoredError;
var
  LError: Exception;
begin
  LError := FError;
  if LError = nil then
    Exit;
  { The task takes over the exception object. }
  FError := nil;
  raise LError;
end;

{ TTaskCompletionSource<TResult>.TValueState }

function TTaskCompletionSource.TValueState.Take: TResult;
begin
  RaiseStoredError;
  Result := Value;
end;

{ TTaskCompletionSource<TResult> }

constructor TTaskCompletionSource.Create;
var
  LState: TValueState;
  LRef: IInterface;
begin
  inherited Create;
  LState := TValueState.Create;
  LRef := LState;
  FState := LState;
  FStateRef := LRef;
  { The body runs only once the source has been completed. It refers to the
    shared state, not to the source, which may already be freed by then. }
  FTask := specialize TFuture<TResult>.Create(nil, nil,
    function: TResult
    begin
      if LRef = nil then;
      Result := LState.Take;
    end,
    TThreadPool.Default);
end;

destructor TTaskCompletionSource.Destroy;
begin
  if Claim then
    FTask.Cancel;
  FTask := nil;
  FStateRef := nil;
  inherited Destroy;
end;

function TTaskCompletionSource.Claim: Boolean;
begin
  Result := InterlockedCompareExchange(FCompleted, 1, 0) = 0;
end;

function TTaskCompletionSource.SetResult(const AResult: TResult): Boolean;
begin
  Result := Claim;
  if not Result then
    Exit;
  FState.Value := AResult;
  FTask.Start;
end;

function TTaskCompletionSource.SetException(const AException: Exception): Boolean;
begin
  Result := Claim;
  if not Result then
  begin
    AException.Free;
    Exit;
  end;
  FState.FError := AException;
  FTask.Start;
end;

function TTaskCompletionSource.SetCanceled: Boolean;
begin
  Result := Claim;
  if not Result then
    Exit;
  { A task that has not been started completes as Canceled at once. }
  FTask.Cancel;
end;

{ TAsyncTaskMethodBuilder<TResult> }

class function TAsyncTaskMethodBuilder.Create: specialize TAsyncTaskMethodBuilder<TResult>;
begin
  Result := Default(specialize TAsyncTaskMethodBuilder<TResult>);
  Result.EnsureSource;
end;

procedure TAsyncTaskMethodBuilder.EnsureSource;
begin
  if (FSource = nil) and (FTask = nil) then
  begin
    FSource := TSource.Create;
    FTask := FSource.Task;
  end;
end;

function TAsyncTaskMethodBuilder.GetTask: specialize IFuture<TResult>;
begin
  EnsureSource;
  Result := FTask;
end;

procedure TAsyncTaskMethodBuilder.Start(const AStateMachine: IAsyncStateMachine);
begin
  EnsureSource;
  AStateMachine.MoveNext;
end;

procedure TAsyncTaskMethodBuilder.AwaitOnCompleted(const ATask: ITask; const AStateMachine: IAsyncStateMachine);
var
  LState: IAsyncStateMachine;
begin
  LState := AStateMachine;
  ATask.ContinueWith(
    procedure(ACompletedTask: ITask)
    begin
      LState.MoveNext;
    end);
end;

procedure TAsyncTaskMethodBuilder.SetResult(const AResult: TResult);
begin
  EnsureSource;
  if FSource <> nil then
  begin
    FSource.SetResult(AResult);
    FreeAndNil(FSource);
  end;
end;

procedure TAsyncTaskMethodBuilder.SetException(const AException: Exception);
begin
  EnsureSource;
  if FSource <> nil then
  begin
    FSource.SetException(AException);
    FreeAndNil(FSource);
  end
  else
    AException.Free;
end;

{ TAsyncTaskBuilder }

class function TAsyncTaskBuilder.Create: TAsyncTaskBuilder;
begin
  Result := Default(TAsyncTaskBuilder);
  Result.EnsureSource;
end;

procedure TAsyncTaskBuilder.EnsureSource;
begin
  if (FSource = nil) and (FTask = nil) then
  begin
    FSource := specialize TTaskCompletionSource<Boolean>.Create;
    FTask := FSource.Task;
  end;
end;

function TAsyncTaskBuilder.GetTask: ITask;
begin
  EnsureSource;
  Result := FTask;
end;

procedure TAsyncTaskBuilder.Start(const AStateMachine: IAsyncStateMachine);
begin
  EnsureSource;
  AStateMachine.MoveNext;
end;

procedure TAsyncTaskBuilder.AwaitOnCompleted(const ATask: ITask; const AStateMachine: IAsyncStateMachine);
var
  LState: IAsyncStateMachine;
begin
  LState := AStateMachine;
  ATask.ContinueWith(
    procedure(ACompletedTask: ITask)
    begin
      LState.MoveNext;
    end);
end;

procedure TAsyncTaskBuilder.SetResult;
begin
  EnsureSource;
  if FSource <> nil then
  begin
    FSource.SetResult(True);
    FreeAndNil(FSource);
  end;
end;

procedure TAsyncTaskBuilder.SetException(const AException: Exception);
begin
  EnsureSource;
  if FSource <> nil then
  begin
    FSource.SetException(AException);
    FreeAndNil(FSource);
  end
  else
    AException.Free;
end;

end.
