{
    Lowers an async routine to a state machine when $ASYNCMODE STATEMACHINE
    is active. The step is a nested function; assigning it to a function
    reference puts captured locals on the heap, so they live across await.

    This program is free software; you can redistribute it and/or modify
    it under the terms of the GNU General Public License as published by
    the Free Software Foundation; either version 2 of the License, or
    (at your option) any later version.
}
unit nasync;

{$i fpcdefs.inc}

interface

    uses
      symdef,node,procinfo;

    procedure prepare_async_statemachine_result(pd: tprocdef);
    procedure finish_async_statemachine_parse(pd: tprocdef);
    function lower_async_statemachine(pd: tprocdef; var code: tnode): boolean;
    function lower_async_fiber(pd: tprocdef; var code: tnode): boolean;

implementation

    uses
      cclasses,cutils,globtype,constexp,verbose,comphook,globals,compinnr,
      symconst,symtype,symbase,symsym,symtable,defutil,fmodule,
      nbas,nutils,ncal,nld,ncon,ncnv,nadd,ninl,nflw,nmat,
      pass_1,pparautl,pgenutil,pgentype,psub,scanner;

    const
      leave_exit = 1;
      leave_break = 2;
      leave_cont = 3;

    type
      tframekind = (fk_loop, fk_finally, fk_except);

      tstate = class
        id: integer;
        block: tblocknode;
        last: tstatementnode;
        constructor create(aid: integer);
        procedure add(n: tnode);
      end;

      tframe = class
        kind: tframekind;
        headid, afterid, outerhandler: integer;
      end;

      tlower = class
        pd: tprocdef;
        outer: tprocinfo;
        states: tfplist;
        frames: tfplist;
        booldef, innerdef: tdef;
        state_sym, handler_sym, leave_sym, leavestop_sym, leaveto_sym,
        except_sym, raise_sym, result_sym: tsym;
        awaitproc, runproc: tprocsym;
        handlerid: integer;
        { True when the body has try/finally or try/except. Only then does
          the step dispatcher need an exception frame on every state. }
        catch_exceptions: boolean;
        stepinfo, getinfo: tprocinfo;
        constructor create(aproc: tprocdef; aouter: tprocinfo);
        destructor destroy; override;
        function new_local(const aname: string; adef: tdef): tsym;
        function new_state: tstate;
        function top_loop: tframe;
        procedure fail(n: tnode; const why: string);
        procedure finish_to(cur: tstate; dest: integer);
        procedure emit_leave(var cur: tstate; reason, target, stop: integer);
        function call_pointer_proc(const aname: string; sym: tsym): tnode;
        function reraise_node: tnode;
        function free_except_node: tnode;
        function handler_end(afterid: integer; reraise: boolean): tnode;
        procedure split_await(stmt: tnode; call: tcallnode; var cur: tstate);
        procedure lower_node(n: tnode; var cur: tstate);
        procedure take_list(list: tstatementnode; var cur: tstate);
        function dispatch_tree: tnode;
        procedure typecheck_step(info: tprocinfo; body: tnode);
        function build(var code: tnode): tnode;
      end;

    var
      funcret_depth: integer;
      funcret_stack: array[0..15] of tsym;
      funcret_pd: array[0..15] of tprocdef;


    function load_sym(sym: tsym): tnode;
      begin
        result:=cloadnode.create(sym,sym.owner);
      end;


    function int_const(v: int64): tnode;
      var
        c: tconstexprint;
      begin
        c:=v;
        result:=cordconstnode.create(c,s32inttype,false);
      end;


    function assign_const(sym: tsym; v: int64): tnode;
      begin
        result:=cassignmentnode.create(load_sym(sym),int_const(v));
      end;


    function copy_assign(dest, src: tsym): tnode;
      begin
        result:=cassignmentnode.create(load_sym(dest),load_sym(src));
      end;


    function await_call_of(n: tnode): tcallnode;
      begin
        result:=nil;
        while assigned(n) and (n.nodetype=typeconvn) do
          n:=ttypeconvnode(n).left;
        if assigned(n) and (n.nodetype=calln) and
           (cnf_await in tcallnode(n).callnodeflags) then
          result:=tcallnode(n);
      end;


    function await_walk(var n: tnode; arg: pointer): foreachnoderesult;
      begin
        result:=fen_false;
        if (n.nodetype=calln) and (cnf_await in tcallnode(n).callnodeflags) then
          begin
            plongint(arg)^:=1;
            result:=fen_norecurse_true;
          end;
      end;


    function has_await(n: tnode): boolean;
      var
        flag: longint;
      begin
        flag:=0;
        if assigned(n) then
          foreachnodestatic(pm_postprocess,n,@await_walk,@flag);
        result:=flag<>0;
      end;


    function exit_walk(var n: tnode; arg: pointer): foreachnoderesult;
      begin
        result:=fen_false;
        if n.nodetype=exitn then
          begin
            plongint(arg)^:=1;
            result:=fen_norecurse_true;
          end;
      end;


    function has_exit(n: tnode): boolean;
      var
        flag: longint;
      begin
        flag:=0;
        if assigned(n) then
          foreachnodestatic(pm_postprocess,n,@exit_walk,@flag);
        result:=flag<>0;
      end;


    { Exit always leaves the async routine. Break and continue do too, unless
      they belong to a loop that stays intact (no await and no exit inside it). }
    function leave_walk(var n: tnode; arg: pointer): foreachnoderesult;
      begin
        result:=fen_false;
        if n.nodetype in [whilerepeatn,forn] then
          begin
            if not has_await(n) and not has_exit(n) then
              result:=fen_norecurse_false;
            exit;
          end;
        if n.nodetype in [exitn,breakn,continuen] then
          begin
            plongint(arg)^:=1;
            result:=fen_norecurse_true;
          end;
      end;


    function has_unscoped_leave(n: tnode): boolean;
      var
        flag: longint;
      begin
        flag:=0;
        if assigned(n) then
          foreachnodestatic(pm_postprocess,n,@leave_walk,@flag);
        result:=flag<>0;
      end;


    function future_value_type(def: tdef): tdef;
      var
        sym: tsym;
        gpd: tprocdef;
      begin
        result:=nil;
        if not assigned(def) or not (def.typ in [objectdef,recorddef]) then
          exit;
        sym:=search_struct_member(tabstractrecorddef(def),'GETVALUE');
        if not assigned(sym) or (sym.typ<>procsym) or
           (tprocsym(sym).procdeflist.count=0) then
          exit;
        gpd:=tprocdef(tprocsym(sym).procdeflist[0]);
        if not is_void(gpd.returndef) then
          result:=gpd.returndef;
      end;


    function find_proc(const aname: tidstring): tprocsym;
      var
        sym: tsym;
        st: tsymtable;
      begin
        result:=nil;
        if searchsym(aname,sym,st) and (sym.typ=procsym) then
          result:=tprocsym(sym);
      end;


    function find_async_state_run: tprocsym;
      var
        dummy: tprocsym;
      begin
        result:=find_proc('ASYNCSTATERUN$1');
        if assigned(result) then
          exit;
        dummy:=find_proc('ASYNCSTATERUN');
        if assigned(dummy) and (sp_generic_dummy in dummy.symoptions) and
           assigned(dummy.genprocsymovlds) and (dummy.genprocsymovlds.count>0) then
          result:=tprocsym(dummy.genprocsymovlds[0]);
      end;


    function capture_walk(var n: tnode; arg: pointer): foreachnoderesult;
      var
        ownerpd: tprocdef;
        sym, target: tsym;
      begin
        result:=fen_false;
        ownerpd:=tprocdef(arg);
        if n.nodetype<>loadn then
          exit;
        sym:=tloadnode(n).symtableentry;
        if (sym.typ=absolutevarsym) and (tabsolutevarsym(sym).abstyp=tovar) and
           assigned(tabsolutevarsym(sym).ref) and
           assigned(tabsolutevarsym(sym).ref.firstsym) then
          begin
            target:=tabsolutevarsym(sym).ref.firstsym^.sym;
            if target.typ=localvarsym then
              begin
                tloadnode(n).symtableentry:=target;
                tloadnode(n).symtable:=target.owner;
                sym:=target;
              end;
          end;
        if (sym.typ in [localvarsym,paravarsym]) and
           ((sym.owner=ownerpd.localst) or (sym.owner=ownerpd.parast)) then
          current_procinfo.procdef.add_captured_sym(sym,tabstractvarsym(sym).vardef,n.fileinfo);
      end;


    function is_async_proc(pd: tprocdef): boolean;
      begin
        result:=assigned(pd) and (pio_async in pd.implprocoptions) and
                not (df_generic in pd.defoptions);
      end;


    function statemachine_proc(pd: tprocdef): boolean;
      begin
        result:=is_async_proc(pd) and
                assigned(current_module) and (current_module.asyncmode=2);
      end;


    function fiber_proc(pd: tprocdef): boolean;
      begin
        result:=is_async_proc(pd) and
                (not assigned(current_module) or (current_module.asyncmode<>2));
      end;


    procedure prepare_async_statemachine_result(pd: tprocdef);
      var
        inner: tdef;
        vs: tlocalvarsym;
        sym: tsym;
        i: integer;
      begin
        if not is_async_proc(pd) then
          exit;
        inner:=future_value_type(pd.returndef);
        if not assigned(inner) then
          exit;
        vs:=clocalvarsym.create('$ASYNCRESULT',vs_value,inner,[vo_is_internal]);
        vs.varstate:=vs_readwritten;
        pd.localst.insertsym(vs);
        for i:=0 to pd.localst.symlist.count-1 do
          begin
            sym:=tsym(pd.localst.symlist[i]);
            if (sym.typ=absolutevarsym) and
               (vo_is_funcret in tabstractvarsym(sym).varoptions) and
               (tabsolutevarsym(sym).abstyp=tovar) and
               assigned(tabsolutevarsym(sym).ref) and
               assigned(tabsolutevarsym(sym).ref.firstsym) then
              begin
                tabsolutevarsym(sym).ref.firstsym^.sym:=vs;
                tabstractvarsym(sym).vardef:=inner;
              end;
          end;
        if funcret_depth>high(funcret_stack) then
          internalerror(2026102101);
        funcret_stack[funcret_depth]:=pd.funcretsym;
        funcret_pd[funcret_depth]:=pd;
        inc(funcret_depth);
        pd.funcretsym:=vs;
      end;


    procedure finish_async_statemachine_parse(pd: tprocdef);
      begin
        if (funcret_depth=0) or (funcret_pd[funcret_depth-1]<>pd) then
          exit;
        dec(funcret_depth);
        pd.funcretsym:=funcret_stack[funcret_depth];
      end;


    constructor tstate.create(aid: integer);
      begin
        id:=aid;
        block:=internalstatements(last);
      end;


    procedure tstate.add(n: tnode);
      begin
        if assigned(n) then
          addstatement(last,n);
      end;


    constructor tlower.create(aproc: tprocdef; aouter: tprocinfo);
      var
        bsym: ttypesym;
      begin
        inherited Create;
        pd:=aproc;
        outer:=aouter;
        states:=tfplist.create;
        frames:=tfplist.create;
        handlerid:=-1;
        bsym:=search_system_type('BOOLEAN');
        if assigned(bsym) then
          booldef:=bsym.typedef
        else
          booldef:=pasbool8type;
        innerdef:=future_value_type(pd.returndef);
        if assigned(innerdef) then
          { The leading $ is stripped and the rest is not uppercased. }
          result_sym:=tsym(pd.localst.find('ASYNCRESULT'));
      end;


    destructor tlower.destroy;
      var
        i: integer;
      begin
        for i:=0 to states.count-1 do
          tstate(states[i]).free;
        states.free;
        for i:=0 to frames.count-1 do
          tframe(frames[i]).free;
        frames.free;
        inherited destroy;
      end;


    function tlower.new_local(const aname: string; adef: tdef): tsym;
      var
        vs: tlocalvarsym;
      begin
        vs:=clocalvarsym.create(aname,vs_value,adef,[vo_is_internal]);
        vs.varstate:=vs_readwritten;
        pd.localst.insertsym(vs);
        result:=vs;
      end;


    function tlower.new_state: tstate;
      begin
        result:=tstate.create(states.count);
        states.add(result);
      end;


    function tlower.top_loop: tframe;
      var
        i: integer;
      begin
        result:=nil;
        for i:=frames.count-1 downto 0 do
          if tframe(frames[i]).kind=fk_loop then
            exit(tframe(frames[i]));
      end;


    procedure tlower.fail(n: tnode; const why: string);
      var
        pos: tfileposinfo;
      begin
        if assigned(n) then
          pos:=n.fileinfo
        else
          pos:=pd.fileinfo;
        messagepos1(pos,parser_e_await_unsupported,why);
      end;


    procedure tlower.finish_to(cur: tstate; dest: integer);
      begin
        cur.add(assign_const(state_sym,dest));
      end;


    procedure tlower.emit_leave(var cur: tstate; reason, target, stop: integer);
      var
        cond: tnode;
      begin
        cur.add(assign_const(leave_sym,reason));
        cur.add(assign_const(leavestop_sym,stop));
        cur.add(assign_const(leaveto_sym,target));
        cond:=caddnode.create(andn,
                caddnode.create(gten,load_sym(handler_sym),int_const(0)),
                caddnode.create(unequaln,load_sym(handler_sym),load_sym(leavestop_sym)));
        cur.add(cifnode.create(cond,
                  copy_assign(state_sym,handler_sym),
                  copy_assign(state_sym,leaveto_sym)));
        cur:=new_state;
      end;


    function tlower.call_pointer_proc(const aname: string; sym: tsym): tnode;
      var
        proc: tprocsym;
      begin
        proc:=find_proc(aname);
        if not assigned(proc) then
          begin
            fail(nil,'System.Threading.'+aname+' is not visible');
            result:=cerrornode.create;
            exit;
          end;
        result:=ccallnode.create(ccallparanode.create(load_sym(sym),nil),
                  proc,proc.owner,nil,[],nil);
      end;


    function tlower.reraise_node: tnode;
      var
        last: tstatementnode;
        b: tblocknode;
      begin
        b:=internalstatements(last);
        addstatement(last,copy_assign(raise_sym,except_sym));
        addstatement(last,cassignmentnode.create(load_sym(except_sym),cnilnode.create));
        addstatement(last,call_pointer_proc('ASYNCRERAISE',raise_sym));
        result:=b;
      end;


    function tlower.free_except_node: tnode;
      begin
        result:=call_pointer_proc('ASYNCRELEASEEXCEPTION',except_sym);
      end;


    function tlower.handler_end(afterid: integer; reraise: boolean): tnode;
      var
        follow, normal: tnode;
      begin
        follow:=cifnode.create(
                  caddnode.create(andn,
                    caddnode.create(gten,load_sym(handler_sym),int_const(0)),
                    caddnode.create(unequaln,load_sym(handler_sym),load_sym(leavestop_sym))),
                  copy_assign(state_sym,handler_sym),
                  copy_assign(state_sym,leaveto_sym));
        if reraise then
          normal:=cifnode.create(
                    caddnode.create(unequaln,load_sym(leave_sym),int_const(0)),
                    follow,
                    assign_const(state_sym,afterid))
        else
          normal:=assign_const(state_sym,afterid);
        if reraise then
          result:=cifnode.create(
                    caddnode.create(unequaln,load_sym(except_sym),cnilnode.create),
                    reraise_node,
                    normal)
        else
          result:=normal;
      end;


    procedure tlower.split_await(stmt: tnode; call: tcallnode; var cur: tstate);
      var
        temp: tsym;
        next: tstate;
        mp, cond: tnode;
      begin
        if not assigned(awaitproc) then
          begin
            fail(call,'System.Threading.AsyncAwait is not visible');
            cur.add(cerrornode.create);
            if stmt<>call then
              stmt.free;
            exit;
          end;
        if not assigned(call.methodpointer) or
           not assigned(call.methodpointer.resultdef) then
          begin
            fail(call,'the awaited expression has no type');
            cur.add(cerrornode.create);
            if stmt<>call then
              stmt.free;
            exit;
          end;
        temp:=new_local('$ASYNCAWAIT'+tostr(states.count),call.methodpointer.resultdef);
        mp:=call.methodpointer;
        call.methodpointer:=load_sym(temp);
        exclude(call.callnodeflags,cnf_await);
        do_typecheckpass(call.methodpointer);
        next:=new_state;
        cur.add(cassignmentnode.create(load_sym(temp),mp));
        { Store the resume state before AsyncAwait. A continuation of this
          await must observe that number, including one armed before this
          call returns. }
        cur.add(assign_const(state_sym,next.id));
        cond:=ccallnode.create(ccallparanode.create(load_sym(temp),nil),
                 awaitproc,awaitproc.owner,nil,[],nil);
        cur.add(cifnode.create(cond,
                 cexitnode.create(cordconstnode.create(1,booldef,false)),
                 nil));
        if assigned(stmt) and (stmt<>call) then
          next.add(stmt)
        else
          next.add(call);
        cur:=next;
      end;


    procedure tlower.take_list(list: tstatementnode; var cur: tstate);
      var
        nxt: tstatementnode;
        n: tnode;
      begin
        while assigned(list) do
          begin
            n:=list.left;
            list.left:=nil;
            nxt:=tstatementnode(list.right);
            list.right:=nil;
            list.free;
            if not assigned(n) or (n.nodetype=nothingn) then
              begin
                if assigned(n) then
                  n.free;
              end
            else if not has_await(n) and not has_unscoped_leave(n) then
              cur.add(n)
            else
              lower_node(n,cur);
            list:=nxt;
          end;
      end;


    procedure tlower.lower_node(n: tnode; var cur: tstate);

      procedure push_frame(kind: tframekind; head, after, outerh: integer);
        var
          frame: tframe;
        begin
          frame:=tframe.create;
          frame.kind:=kind;
          frame.headid:=head;
          frame.afterid:=after;
          frame.outerhandler:=outerh;
          frames.add(frame);
        end;

      procedure pop_frame;
        begin
          tframe(frames[frames.count-1]).free;
          frames.delete(frames.count-1);
        end;

      var
        call: tcallnode;
        cond, body, other, fromn, ton, loopvar: tnode;
        head, bodys, afters, fins, exs, step: tstate;
        bodycur, fincur, excur: tstate;
        saved: tsym;
        lflags: tloopflags;
        backward: boolean;
        cmp: tnodetype;
        incnum: tinlinenumber;
        list: tstatementnode;
        oldhandler: integer;
        loop: tframe;
      begin
        if not assigned(n) then
          exit;
        call:=await_call_of(n);
        if assigned(call) then
          begin
            split_await(n,call,cur);
            exit;
          end;
        case n.nodetype of
          blockn:
            begin
              list:=tstatementnode(tblocknode(n).left);
              tblocknode(n).left:=nil;
              n.free;
              take_list(list,cur);
            end;
          assignn:
            begin
              call:=await_call_of(tbinarynode(n).right);
              if assigned(call) then
                split_await(n,call,cur)
              else
                begin
                  fail(n,'await inside an expression');
                  n.free;
                  cur.add(cerrornode.create);
                end;
            end;
          ifn:
            begin
              cond:=tifnode(n).left;
              body:=tifnode(n).right;
              other:=tifnode(n).t1;
              tifnode(n).left:=nil;
              tifnode(n).right:=nil;
              tifnode(n).t1:=nil;
              n.free;
              if has_await(cond) then
                begin
                  fail(cond,'await in a condition');
                  cond.free;
                  cond:=cordconstnode.create(0,booldef,false);
                end;
              head:=new_state;
              bodys:=new_state;
              afters:=new_state;
              cur.add(cifnode.create(cond,
                        assign_const(state_sym,head.id),
                        assign_const(state_sym,bodys.id)));
              bodycur:=head;
              if assigned(body) then
                lower_node(body,bodycur);
              finish_to(bodycur,afters.id);
              bodycur:=bodys;
              if assigned(other) then
                lower_node(other,bodycur);
              finish_to(bodycur,afters.id);
              cur:=afters;
            end;
          whilerepeatn:
            begin
              lflags:=twhilerepeatnode(n).loopflags;
              cond:=twhilerepeatnode(n).left;
              body:=twhilerepeatnode(n).right;
              twhilerepeatnode(n).left:=nil;
              twhilerepeatnode(n).right:=nil;
              n.free;
              if has_await(cond) then
                begin
                  fail(cond,'await in a condition');
                  cond.free;
                  cond:=cordconstnode.create(1,booldef,false);
                end;
              if (lnf_checknegate in lflags) and (lnf_testatbegin in lflags) then
                cond:=cnotnode.create(cond);
              head:=new_state;
              afters:=new_state;
              finish_to(cur,head.id);
              if lnf_testatbegin in lflags then
                begin
                  bodys:=new_state;
                  push_frame(fk_loop,head.id,afters.id,handlerid);
                  { A previous iteration's continue flag must not make this
                    iteration's finally skip the loop step. }
                  head.add(assign_const(leave_sym,0));
                  head.add(cifnode.create(cond,
                            assign_const(state_sym,bodys.id),
                            assign_const(state_sym,afters.id)));
                  bodycur:=bodys;
                  if assigned(body) then
                    lower_node(body,bodycur);
                  emit_leave(bodycur,leave_cont,head.id,handlerid);
                end
              else
                begin
                  { continue in repeat lands on the until test, not the body. }
                  step:=new_state;
                  push_frame(fk_loop,step.id,afters.id,handlerid);
                  bodycur:=head;
                  if assigned(body) then
                    lower_node(body,bodycur);
                  emit_leave(bodycur,leave_cont,step.id,handlerid);
                  step.add(assign_const(leave_sym,0));
                  step.add(cifnode.create(cond,
                                assign_const(state_sym,afters.id),
                                assign_const(state_sym,head.id)));
                end;
              pop_frame;
              cur:=afters;
            end;
          forn:
            begin
              if tfornode(n).left.nodetype<>loadn then
                begin
                  fail(n,'for-in');
                  n.free;
                  cur.add(cerrornode.create);
                  exit;
                end;
              backward:=lnf_backward in tfornode(n).loopflags;
              loopvar:=tfornode(n).left;
              fromn:=tfornode(n).right;
              ton:=tfornode(n).t1;
              body:=tfornode(n).t2;
              tfornode(n).left:=nil;
              tfornode(n).right:=nil;
              tfornode(n).t1:=nil;
              tfornode(n).t2:=nil;
              n.free;
              if has_await(fromn) or has_await(ton) then
                begin
                  fail(fromn,'await in a for bound');
                  fromn.free;
                  ton.free;
                  loopvar.free;
                  if assigned(body) then
                    body.free;
                  cur.add(cerrornode.create);
                  exit;
                end;
              cur.add(cassignmentnode.create(loopvar.getcopy,fromn));
              if backward then
                begin
                  cmp:=gten;
                  incnum:=in_pred_x;
                end
              else
                begin
                  cmp:=lten;
                  incnum:=in_succ_x;
                end;
              head:=new_state;
              bodys:=new_state;
              step:=new_state;
              afters:=new_state;
              finish_to(cur,head.id);
              head.add(assign_const(leave_sym,0));
              head.add(cifnode.create(
                        caddnode.create(cmp,loopvar.getcopy,ton),
                        assign_const(state_sym,bodys.id),
                        assign_const(state_sym,afters.id)));
              { The for-step is its own state, so continue still advances the
                control variable and only then repeats the test. }
              push_frame(fk_loop,step.id,afters.id,handlerid);
              bodycur:=bodys;
              if assigned(body) then
                lower_node(body,bodycur);
              finish_to(bodycur,step.id);
              step.add(cassignmentnode.create(loopvar.getcopy,
                        cinlinenode.createintern(incnum,false,loopvar.getcopy)));
              emit_leave(step,leave_cont,head.id,handlerid);
              pop_frame;
              loopvar.free;
              cur:=afters;
            end;
          tryfinallyn:
            begin
              catch_exceptions:=true;
              body:=ttryfinallynode(n).left;
              other:=ttryfinallynode(n).right;
              ttryfinallynode(n).left:=nil;
              ttryfinallynode(n).right:=nil;
              n.free;
              fins:=new_state;
              afters:=new_state;
              bodys:=new_state;
              saved:=new_local('$ASYNCSAVED'+tostr(fins.id),s32inttype);
              cur.add(cassignmentnode.create(load_sym(saved),load_sym(handler_sym)));
              cur.add(assign_const(handler_sym,fins.id));
              finish_to(cur,bodys.id);
              oldhandler:=handlerid;
              handlerid:=fins.id;
              push_frame(fk_finally,fins.id,afters.id,oldhandler);
              bodycur:=bodys;
              if assigned(body) then
                lower_node(body,bodycur);
              finish_to(bodycur,fins.id);
              pop_frame;
              handlerid:=oldhandler;
              fincur:=fins;
              fincur.add(copy_assign(handler_sym,saved));
              if assigned(other) then
                lower_node(other,fincur);
              fincur.add(handler_end(afters.id,true));
              cur:=afters;
            end;
          tryexceptn:
            begin
              catch_exceptions:=true;
              if assigned(ttryexceptnode(n).right) and has_await(n) then
                begin
                  fail(n,'await in an ''on'' handler');
                  n.free;
                  cur.add(cerrornode.create);
                  exit;
                end;
              body:=ttryexceptnode(n).left;
              other:=ttryexceptnode(n).t1;
              ttryexceptnode(n).left:=nil;
              ttryexceptnode(n).t1:=nil;
              n.free;
              exs:=new_state;
              afters:=new_state;
              bodys:=new_state;
              saved:=new_local('$ASYNCSAVED'+tostr(exs.id),s32inttype);
              cur.add(cassignmentnode.create(load_sym(saved),load_sym(handler_sym)));
              cur.add(assign_const(handler_sym,exs.id));
              finish_to(cur,bodys.id);
              oldhandler:=handlerid;
              handlerid:=exs.id;
              push_frame(fk_except,exs.id,afters.id,oldhandler);
              bodycur:=bodys;
              if assigned(body) then
                lower_node(body,bodycur);
              bodycur.add(copy_assign(handler_sym,saved));
              finish_to(bodycur,afters.id);
              pop_frame;
              handlerid:=oldhandler;
              excur:=exs;
              excur.add(copy_assign(handler_sym,saved));
              excur.add(free_except_node);
              excur.add(cassignmentnode.create(load_sym(except_sym),cnilnode.create));
              excur.add(assign_const(leave_sym,0));
              if assigned(other) then
                lower_node(other,excur);
              finish_to(excur,afters.id);
              cur:=afters;
            end;
          exitn:
            begin
              if assigned(texitnode(n).resultexpr) then
                begin
                  cur.add(texitnode(n).resultexpr);
                  texitnode(n).resultexpr:=nil;
                end;
              n.free;
              emit_leave(cur,leave_exit,0,-2);
              { 0 is filled once done exists; patched by the caller via state 0 }
            end;
          breakn, continuen:
            begin
              loop:=top_loop;
              if not assigned(loop) then
                begin
                  fail(n,'break or continue outside a loop');
                  n.free;
                  cur.add(cerrornode.create);
                end
              else if n.nodetype=breakn then
                begin
                  n.free;
                  emit_leave(cur,leave_break,loop.afterid,loop.outerhandler);
                end
              else
                begin
                  n.free;
                  emit_leave(cur,leave_cont,loop.headid,loop.outerhandler);
                end;
            end;
          else
            begin
              fail(n,'this statement');
              n.free;
              cur.add(cerrornode.create);
            end;
        end;
      end;


    function tlower.dispatch_tree: tnode;
      var
        i: integer;
        chain, trap: tnode;
        last: tstatementnode;
        handler: tblocknode;
      begin
        chain:=cexitnode.create(cordconstnode.create(0,booldef,false));
        for i:=states.count-1 downto 0 do
          chain:=cifnode.create(
                   caddnode.create(equaln,load_sym(state_sym),int_const(tstate(states[i]).id)),
                   tstate(states[i]).block,
                   chain);
        handler:=internalstatements(last);
        { A finally that already holds an exception and then raises again
          drops the previous object; Pascal keeps only the new one. }
        addstatement(last,cifnode.create(
          caddnode.create(unequaln,load_sym(except_sym),cnilnode.create),
          free_except_node,nil));
        addstatement(last,cassignmentnode.create(load_sym(except_sym),
          ccallnode.createintern('ACQUIREEXCEPTIONOBJECT',nil)));
        addstatement(last,copy_assign(state_sym,handler_sym));
        addstatement(last,assign_const(handler_sym,-1));
        { TAsyncStateMachine.Run already catches an exception that leaves the
          step. A frame on every state is only needed to divert a raise into
          a user finally or except handler. }
        if catch_exceptions then
          begin
            trap:=cifnode.create(
                    caddnode.create(gten,load_sym(handler_sym),int_const(0)),
                    handler,
                    craisenode.create(nil,nil,nil));
            chain:=ctryexceptnode.create(chain,nil,trap);
          end
        else
          handler.free;
        result:=cwhilerepeatnode.create(
                  cordconstnode.create(1,booldef,false),
                  chain,
                  true,false);
      end;


    procedure tlower.typecheck_step(info: tprocinfo; body: tnode);
      var
        saved: tprocinfo;
      begin
        saved:=current_procinfo;
        current_procinfo:=info;
        tcgprocinfo(info).add_to_symtablestack;
        do_typecheckpass(body);
        foreachnodestatic(pm_postprocess,body,@capture_walk,pd);
        tcgprocinfo(info).code:=body;
        tcgprocinfo(info).remove_from_symtablestack;
        current_procinfo:=saved;
      end;


    function tlower.build(var code: tnode): tnode;
      var
        cur: tstate;
        list: tstatementnode;
        savedpi: tprocinfo;
        stepbody, getbody: tnode;
        outlast: tstatementnode;
        ctx: tspecializationcontext;
        posinfo: pfileposinfo;
        stepn, getn, call: tnode;
        startid: integer;
      begin
        result:=nil;
        if not has_await(code) and not assigned(innerdef) then
          exit;
        if has_await(code) then
          begin
            awaitproc:=find_proc('ASYNCAWAIT');
            if not assigned(awaitproc) then
              begin
                fail(code,'System.Threading.AsyncAwait is not visible');
                exit;
              end;
          end;
        if assigned(innerdef) then
          begin
            runproc:=find_async_state_run;
            if not assigned(runproc) then
              begin
                fail(code,'System.Threading.AsyncStateRun is not visible');
                exit;
              end;
            if not assigned(result_sym) then
              begin
                fail(code,'the async result variable is missing');
                exit;
              end;
            if not assigned(innerdef.typesym) then
              begin
                fail(code,'the async result type has no name');
                exit;
              end;
          end
        else
          begin
            runproc:=find_proc('ASYNCSTATERUNTASK');
            if not assigned(runproc) then
              begin
                fail(code,'System.Threading.AsyncStateRunTask is not visible');
                exit;
              end;
          end;

        state_sym:=new_local('$ASYNCSTATE',s32inttype);
        handler_sym:=new_local('$ASYNCHANDLER',s32inttype);
        leave_sym:=new_local('$ASYNCLEAVE',s32inttype);
        leavestop_sym:=new_local('$ASYNCLEAVESTOP',s32inttype);
        leaveto_sym:=new_local('$ASYNCLEAVETO',s32inttype);
        except_sym:=new_local('$ASYNCEXCEPT',voidpointertype);
        raise_sym:=new_local('$ASYNCRAISE',voidpointertype);

        stepinfo:=outer.create_for_outlining('$asyncstep',nil,potype_function,booldef,code);
        { Function-reference interfaces are keyed by the source position.
          The step and the result reader are both born at the user's
          statement, so give them distinct positions or they collapse into
          one interface and the step is never called. }
        stepinfo.procdef.fileinfo.column:=1;
        stepinfo.procdef.procsym.fileinfo.column:=1;
        insert_funcret_local(stepinfo.procdef);
        include(stepinfo.flags,pi_do_call);
        include(stepinfo.flags,pi_uses_exceptions);
        stepinfo.procdef.is_implemented:=true;

        savedpi:=current_procinfo;
        current_procinfo:=stepinfo;
        { State 0 finishes the step. The body starts at the next state. }
        cur:=new_state;
        cur.add(cexitnode.create(cordconstnode.create(0,booldef,false)));
        cur:=new_state;
        startid:=cur.id;
        if code.nodetype=blockn then
          begin
            list:=tstatementnode(tblocknode(code).left);
            tblocknode(code).left:=nil;
            code.free;
            code:=nil;
            take_list(list,cur);
          end
        else
          begin
            list:=cstatementnode.create(code,nil);
            code:=nil;
            take_list(list,cur);
          end;
        finish_to(cur,0);

        stepbody:=cblocknode.create(cstatementnode.create(dispatch_tree,nil));
        typecheck_step(stepinfo,stepbody);
        current_procinfo:=savedpi;

        getn:=nil;
        if assigned(innerdef) then
          begin
            getinfo:=outer.create_for_outlining('$asyncget',nil,potype_function,innerdef,stepbody);
            getinfo.procdef.fileinfo.column:=2;
            getinfo.procdef.procsym.fileinfo.column:=2;
            insert_funcret_local(getinfo.procdef);
            getinfo.procdef.is_implemented:=true;
            current_procinfo:=getinfo;
            getbody:=cassignmentnode.create(
                       load_sym(getinfo.procdef.funcretsym),
                       load_sym(result_sym));
            getbody:=cblocknode.create(cstatementnode.create(getbody,nil));
            typecheck_step(getinfo,getbody);
            current_procinfo:=savedpi;
            getn:=cloadnode.create(getinfo.procdef.procsym,getinfo.procdef.procsym.owner);
          end;

        stepn:=cloadnode.create(stepinfo.procdef.procsym,stepinfo.procdef.procsym.owner);
        if assigned(innerdef) then
          begin
            ctx:=tspecializationcontext.create;
            ctx.paramlist.add(innerdef.typesym);
            new(posinfo);
            posinfo^:=pd.fileinfo;
            ctx.poslist.add(posinfo);
            ctx.genname:=runproc.realname;
            make_prettystring(innerdef,true,'',ctx.prettyname,ctx.specializename);
            { The parameter list is stored last-argument-first, as the parser does. }
            call:=ccallnode.create(
                    ccallparanode.create(getn,ccallparanode.create(stepn,nil)),
                    runproc,runproc.owner,nil,[],ctx);
          end
        else
          call:=ccallnode.create(ccallparanode.create(stepn,nil),
                  runproc,runproc.owner,nil,[],nil);

        if not is_void(pd.returndef) then
          call:=cassignmentnode.create(
                  cloadnode.create(pd.funcretsym,pd.funcretsym.owner),
                  call);

        result:=internalstatements(outlast);
        addstatement(outlast,assign_const(state_sym,startid));
        addstatement(outlast,assign_const(handler_sym,-1));
        addstatement(outlast,assign_const(leave_sym,0));
        addstatement(outlast,cassignmentnode.create(load_sym(except_sym),cnilnode.create));
        addstatement(outlast,call);
      end;


    function lower_async_statemachine(pd: tprocdef; var code: tnode): boolean;
      var
        lw: tlower;
        nw: tnode;
      begin
        result:=false;
        if not assigned(code) or not statemachine_proc(pd) then
          exit;
        lw:=tlower.create(pd,current_procinfo);
        nw:=lw.build(code);
        lw.free;
        if assigned(nw) then
          begin
            code:=nw;
            result:=true;
          end;
      end;


    type
      treplace_ret_info = record
        old_sym: tsym;
        new_sym: tsym;
      end;

    function replace_funcret_walk(var n: tnode; arg: pointer): foreachnoderesult;
      var
        info: ^treplace_ret_info;
        sym, target: tsym;
      begin
        result:=fen_false;
        info:=arg;
        if n.nodetype<>loadn then
          exit;
        sym:=tloadnode(n).symtableentry;
        if (sym.typ in [localvarsym,paravarsym,absolutevarsym]) and
           (vo_is_funcret in tabstractvarsym(sym).varoptions) then
          begin
            tloadnode(n).symtableentry:=info^.new_sym;
            tloadnode(n).symtable:=info^.new_sym.owner;
            tabstractvarsym(info^.new_sym).varstate:=vs_readwritten;
            inc(info^.new_sym.refs);
            exit;
          end;
        if (sym=info^.old_sym) or (sym.name='ASYNCRESULT') or (sym.realname='ASYNCRESULT') then
          begin
            tloadnode(n).symtableentry:=info^.new_sym;
            tloadnode(n).symtable:=info^.new_sym.owner;
            tabstractvarsym(info^.new_sym).varstate:=vs_readwritten;
            inc(info^.new_sym.refs);
            exit;
          end;
        if (sym.typ=absolutevarsym) and (tabsolutevarsym(sym).abstyp=tovar) and
           assigned(tabsolutevarsym(sym).ref) and
           assigned(tabsolutevarsym(sym).ref.firstsym) then
          begin
            target:=tabsolutevarsym(sym).ref.firstsym^.sym;
            if (target=info^.old_sym) or (target.name='ASYNCRESULT') or (target.realname='ASYNCRESULT') then
              begin
                tloadnode(n).symtableentry:=info^.new_sym;
                tloadnode(n).symtable:=info^.new_sym.owner;
                tabstractvarsym(info^.new_sym).varstate:=vs_readwritten;
                inc(info^.new_sym.refs);
                exit;
              end;
          end;
      end;


    procedure typecheck_fiber_body(info: tprocinfo; body: tnode; outerpd: tprocdef);
      var
        saved: tprocinfo;
      begin
        saved:=current_procinfo;
        current_procinfo:=info;
        tcgprocinfo(info).add_to_symtablestack;
        do_typecheckpass(body);
        foreachnodestatic(pm_postprocess,body,@capture_walk,outerpd);
        tcgprocinfo(info).code:=body;
        tcgprocinfo(info).remove_from_symtablestack;
        current_procinfo:=saved;
      end;


    function find_fiber_async_proc(out obj_node: tnode; out obj_st: tsymtable): tprocsym;
      var
        sym: tsym;
        st: tsymtable;
        dummy: tprocsym;
      begin
        result:=nil;
        obj_node:=nil;
        obj_st:=nil;
        { 1. Flat function AsyncFiberRun<T> }
        if searchsym('ASYNCFIBERRUN$1',sym,st) and (sym.typ=procsym) then
          begin
            result:=tprocsym(sym);
            exit;
          end;
        if searchsym('ASYNCFIBERRUN',sym,st) and (sym.typ=procsym) then
          begin
            dummy:=tprocsym(sym);
            if (sp_generic_dummy in dummy.symoptions) and
               assigned(dummy.genprocsymovlds) and (dummy.genprocsymovlds.count>0) then
              result:=tprocsym(dummy.genprocsymovlds[0])
            else
              result:=dummy;
            exit;
          end;
        { 2. Flat function RunAsync<T> }
        if searchsym('RUNASYNC$1',sym,st) and (sym.typ=procsym) then
          begin
            result:=tprocsym(sym);
            exit;
          end;
        if searchsym('RUNASYNC',sym,st) and (sym.typ=procsym) then
          begin
            dummy:=tprocsym(sym);
            if (sp_generic_dummy in dummy.symoptions) and
               assigned(dummy.genprocsymovlds) and (dummy.genprocsymovlds.count>0) then
              result:=tprocsym(dummy.genprocsymovlds[0])
            else
              result:=dummy;
            exit;
          end;
        { 3. Class method TFiber.Async<T> }
        if searchsym('TFIBER',sym,st) and (sym.typ=typesym) and
           assigned(ttypesym(sym).typedef) and (ttypesym(sym).typedef.typ in [objectdef,recorddef]) then
          begin
            obj_st:=tabstractrecorddef(ttypesym(sym).typedef).symtable;
            sym:=search_struct_member(tabstractrecorddef(ttypesym(sym).typedef),'ASYNC$1');
            if not assigned(sym) then
              sym:=search_struct_member(tabstractrecorddef(ttypesym(sym).typedef),'ASYNC');
            if assigned(sym) and (sym.typ=procsym) then
              begin
                dummy:=tprocsym(sym);
                if (sp_generic_dummy in dummy.symoptions) and
                   assigned(dummy.genprocsymovlds) and (dummy.genprocsymovlds.count>0) then
                  result:=tprocsym(dummy.genprocsymovlds[0])
                else
                  result:=dummy;
                obj_node:=ctypenode.create(tabstractrecorddef(sym.owner.defowner));
                exit;
              end;
          end;
      end;


    function find_fiber_spawn_proc(out obj_node: tnode; out obj_st: tsymtable): tprocsym;
      var
        sym: tsym;
        st: tsymtable;
      begin
        result:=nil;
        obj_node:=nil;
        obj_st:=nil;
        { 1. Flat function AsyncFiberRunTask }
        if searchsym('ASYNCFIBERRUNTASK',sym,st) and (sym.typ=procsym) then
          begin
            result:=tprocsym(sym);
            exit;
          end;
        { 2. Flat function SpawnAsync }
        if searchsym('SPAWNASYNC',sym,st) and (sym.typ=procsym) then
          begin
            result:=tprocsym(sym);
            exit;
          end;
        { 3. Class method TFiber.Spawn }
        if searchsym('TFIBER',sym,st) and (sym.typ=typesym) and
           assigned(ttypesym(sym).typedef) and (ttypesym(sym).typedef.typ in [objectdef,recorddef]) then
          begin
            obj_st:=tabstractrecorddef(ttypesym(sym).typedef).symtable;
            sym:=search_struct_member(tabstractrecorddef(ttypesym(sym).typedef),'SPAWN');
            if assigned(sym) and (sym.typ=procsym) then
              begin
                result:=tprocsym(sym);
                obj_node:=ctypenode.create(tabstractrecorddef(sym.owner.defowner));
                exit;
              end;
          end;
      end;


    function lower_async_fiber(pd: tprocdef; var code: tnode): boolean;
      var
        innerdef: tdef;
        potype: tproctypeoption;
        resdef: tdef;
        fiberinfo: tprocinfo;
        fibern, call: tnode;
        runproc: tprocsym;
        run_obj: tnode;
        run_st: tsymtable;
        ctx: tspecializationcontext;
        posinfo: pfileposinfo;
        outlast: tstatementnode;
        bodycode: tnode;
        ret_info: treplace_ret_info;
      begin
        result:=false;
        if not assigned(code) or not fiber_proc(pd) then
          exit;
        innerdef:=future_value_type(pd.returndef);
        if assigned(innerdef) then
          begin
            potype:=potype_function;
            resdef:=innerdef;
            if not assigned(innerdef.typesym) then
              begin
                messagepos1(pd.fileinfo,parser_e_await_unsupported,'the async result type has no name');
                exit;
              end;
            runproc:=find_fiber_async_proc(run_obj,run_st);
            if not assigned(runproc) then
              begin
                messagepos1(pd.fileinfo,parser_e_await_unsupported,'async fiber runtime (AsyncFiberRun, TFiber.Async, or RunAsync) is not visible; ensure fclasync or async.fiber is in uses');
                exit;
              end;
          end
        else
          begin
            potype:=potype_procedure;
            resdef:=voidtype;
            runproc:=find_fiber_spawn_proc(run_obj,run_st);
            if not assigned(runproc) then
              begin
                messagepos1(pd.fileinfo,parser_e_await_unsupported,'async fiber runtime (AsyncFiberRunTask, TFiber.Spawn, or SpawnAsync) is not visible; ensure fclasync or async.fiber is in uses');
                exit;
              end;
          end;

        fiberinfo:=current_procinfo.create_for_outlining('$asyncfiber',nil,potype,resdef,code);
        fiberinfo.procdef.fileinfo:=pd.fileinfo;
        fiberinfo.procdef.procsym.fileinfo:=pd.fileinfo;
        if potype=potype_function then
          begin
            insert_funcret_local(fiberinfo.procdef);
            tabstractvarsym(fiberinfo.procdef.funcretsym).varstate:=vs_readwritten;
            inc(fiberinfo.procdef.funcretsym.refs);
          end;
        include(fiberinfo.flags,pi_do_call);
        include(fiberinfo.flags,pi_uses_exceptions);
        fiberinfo.procdef.is_implemented:=true;

        bodycode:=code;
        code:=nil;
        if potype=potype_function then
          begin
            ret_info.old_sym:=tsym(pd.localst.find('ASYNCRESULT'));
            if not assigned(ret_info.old_sym) then
              ret_info.old_sym:=tsym(pd.localst.find('$ASYNCRESULT'));
            ret_info.new_sym:=fiberinfo.procdef.funcretsym;
            foreachnodestatic(pm_postprocess,bodycode,@replace_funcret_walk,@ret_info);
          end;

        typecheck_fiber_body(fiberinfo,bodycode,pd);

        fibern:=cloadnode.create(fiberinfo.procdef.procsym,fiberinfo.procdef.procsym.owner);
        if assigned(innerdef) then
          begin
            ctx:=tspecializationcontext.create;
            ctx.paramlist.add(innerdef.typesym);
            new(posinfo);
            posinfo^:=pd.fileinfo;
            ctx.poslist.add(posinfo);
            ctx.genname:=runproc.realname;
            make_prettystring(innerdef,true,'',ctx.prettyname,ctx.specializename);
            if assigned(run_obj) then
              call:=ccallnode.create(
                      ccallparanode.create(fibern,nil),
                      runproc,run_st,run_obj,[cnf_member_call],ctx)
            else
              call:=ccallnode.create(
                      ccallparanode.create(fibern,nil),
                      runproc,runproc.owner,nil,[],ctx);
            call:=cassignmentnode.create(
                    cloadnode.create(pd.funcretsym,pd.funcretsym.owner),
                    call);
          end
        else
          begin
            if assigned(run_obj) then
              call:=ccallnode.create(
                      ccallparanode.create(fibern,nil),
                      runproc,run_st,run_obj,[cnf_member_call],nil)
            else
              call:=ccallnode.create(
                      ccallparanode.create(fibern,nil),
                      runproc,runproc.owner,nil,[],nil);
          end;

        code:=internalstatements(outlast);
        addstatement(outlast,call);
        result:=true;
      end;

end.
