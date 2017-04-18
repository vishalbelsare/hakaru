#This module implements `Partition`---Hakaru's replacement for Maple's
#endogenous and unwieldy `piecewise`.

#The outer data structure for a Partition is a function, PARTITION(...), (just like it
#is for piecewise.
Partition:= module()
  option package;

  # Constructor for Partition pieces
  global Piece;

local
  Umap := proc(f,x,$)
    f(op(0,x))( map( p -> Piece(f(condOf(p)),f(valOf(p))), op(1,x) ))
  end proc,

  isPartitionPieceOf := proc( p, elem_t := anything )
    type(p, 'Piece(PartitionCond, elem_t)');
  end proc,

  isPartitionOf := proc( e, elem_t := anything )
    type(e, 'PARTITION(list(PartitionPiece(elem_t)))' );
  end proc,

  ModuleLoad::static:= proc()
    :-`print/PARTITION`:=
    proc(SetOfRecords)
    local branch;
      `print/%piecewise`(
        seq([ condOf(eval(branch)), valOf(eval(branch))][], branch= SetOfRecords))
    end proc;

    TypeTools:-AddType(PartitionCond, {relation, boolean, `::`, specfunc({`And`,`Or`,`Not`}), `and`, `or`, `not`});
    TypeTools:-AddType(PartitionPiece, isPartitionPieceOf);
    TypeTools:-AddType(Partition, isPartitionOf);

    # global extensions to maple functionality
    :-`eval/PARTITION` :=
    proc(p, eqs, $)
      Partition:-Simpl(Umap(x->eval(x,eqs), p));
    end proc;

    :-`depends/PARTITION` :=
    proc(parts, nms, $)
    local dp := (x -> depends(x, nms));
      `or`(op ( map(p-> dp(condOf(p)) or dp(valOf(p)), parts) ));
    end proc;

    :-`diff/PARTITION` :=
    proc(parts, wrt, $)
    local pw  := PartitionToPW(PARTITION(parts))
        , dpw := diff(pw, wrt)
        , r   := PWToPartition(dpw, 'do_solve')
        , r0, r1;
      r0 := Simpl:-singular_pts(r);

      # probably a better way to do this; we really only want to simplify
      # sums and products of integrals and summations
      r1 := subsindets(r0, algebraic, `simplify`);

      userinfo(10, 'disint_trace',
               printf("  input        : \n\t%a\n\n"
                      "  diff         : \n\t%a\n\n"
                      "  singular pts : \n\t%a\n\n"
                      "  simplified   : \n\t%a\n\n\n"
                      , parts, r, r0, r1 ));

      r1;
    end proc;

    :-`simplify/PARTITION` := Simpl;

    NULL
  end proc,

  ModuleUnload::static:= proc()
    TypeTools:-RemoveType(Partition);
    TypeTools:-RemoveType(PartitionPiece);
    NULL
  end proc,

  # abstract out all argument checking for map-like functions
  map_check := proc(p)
  local pos, err;
    if p::indexed then
      pos:= op(p);
      if not [pos]::[posint] then
        err := sprintf("Expected positive integer index; received %a", [pos]);
        return err;
      end if
    else
      pos:= 1
    end if;
    if nargs-1 <= pos then
      err := sprintf("Expected at least %d arguments; received %d", pos+1, nargs-1);
      return err;
    end if;
    if not args[pos+2]::Partition then
      err := sprintf("Expected a Partition; received %a", args[pos+2]);
      return err;
    end if;
    return pos;
  end proc,

  extr_conjs := proc(x,$)
    if x::{specfunc(`And`), `and`} then
      map(extr_conjs, [op(x)])[];
    else
      x
    end if
  end proc;
export
  condOf := proc(x::specfunc(`Piece`),$)
    op(1,x);
  end proc,

  valOf := proc(x::specfunc(`Piece`),$)
    op(2,x);
  end proc,

  Pieces := proc(cs0,es0)::list(PartitionPiece);
    local es, cs;
    es := `if`(es0::{set,list},x->x,x->{x})(es0);
    cs := `if`(cs0::{set,list,specfunc(`And`),`and`},x->x,x->{x})(cs0);
    [seq(seq(Piece(c,e),c=cs),e=es)];
  end proc,

  #This is just `map` for Partitions.
  #Allow additional args, just like `map`
  Pmap::static:= proc(f)::Partition;
    local pair,pos,res;
    res := map_check(procname, args);
    if res::string then error res else pos := res; end if;
    PARTITION([seq(
      Piece(condOf(pair)
            ,f(args[2..pos], valOf(pair), args[pos+2..])
         ),pair= op(1, args[pos+1]))])
  end proc,

  # a more complex mapping combinator which works on all 3 parts
  # not fully general, but made to work with KB
  # also, does not handle extra arguments (on purpose!)
  Amap::static:= proc(
    funcs::[anything, anything, anything], #`appliable` not inclusive enough.
    part::Partition)::Partition;
    local pair,pos,f,g,h,doIt;
    (f,g,h) := op(funcs);
    #sigh, we don't have a decent 'let', need to use a local proc
    doIt := proc(pair)
    local kb0 := h(condOf(pair));
      Piece( f(condOf(pair), kb0),
             g(valOf(pair), kb0));
    end proc;
    PARTITION(map(doIt,op(1,part)));
  end proc,

  Foldr := proc( cons, nil, prt :: Partition, $ )
    foldr(proc(p, x) cons(condOf(p), valOf(p), x); end proc,nil,op(op(1, prt)));
  end proc,

  Foldr_mb := proc( cons, nil, prt, $ )
    if prt :: Partition then Foldr(_passed)
    else                     cons( true, prt, nil ) end if;
  end proc,

  PartitionToPW_mb := proc(x, $)
    if x :: Partition then PartitionToPW(x) else x end if;
  end proc,

  PartitionToPW := module()
    export ModuleApply; local pw_cond_ctx;
    ModuleApply := proc(x::Partition, $)
    local parts := op(1,x);
      if nops(parts) = 1 and is(op([1,1],parts)) then return op([1,2], parts) end if;
      parts := foldl(pw_cond_ctx, [ [], {} ], op(parts) );
      parts := [seq([condOf(p), valOf(p)][], p=op(1,parts))];
      if op(-2, parts) :: identical(true) then
        parts := subsop(-2=NULL, parts);
    end if;
      piecewise(op(parts));
    end proc;

    pw_cond_ctx := proc(ctx_, p, $)
    local ps, ctx, ctxN, cond, ncond;
      ps, ctx := op(ctx_); cond := condOf(p);
      cond := {extr_conjs(cond)};
      cond := remove(x->x in ctx, cond);
      ncond := `if`(nops(cond)=1
                    , KB:-negate_rel(op(1,cond))
                    , `Not`(bool_And(op(cond))) );
      cond := bool_And(op(cond));
      ctx := ctx union { ncond };
      [ [ op(ps), Piece(cond, valOf(p)) ], ctx ]
    end proc;
  end module,

  Flatten := module()
    export ModuleApply;
    local unpiece, unpart, unpartProd;

    ModuleApply := proc(pr0, { _with := [ 'Partition', unpart ] } )
      local ty, un_ty, pr1, pr2;
      ty, un_ty := op(_with);

      pr1 := subsindets(pr0, ty, un_ty);
      if pr0 <> pr1 then
        ModuleApply(pr1, _with=[ Or('Partiton',`*`), unpartProd ]);
      else
        pr0
      end if;
    end proc;

    # like Piece, but tries to not be a Piece
    unpiece := proc(c, pr, $)
      if pr :: Partition then
        map(q -> applyop(z->bool_And(z,c),1,q), op(1,pr))[]
      else Piece(c, pr) end if
    end proc;

    unpart := proc(pr, $)
      if pr :: Partition then
        PARTITION(map(q -> unpiece(condOf(q),valOf(q)), op(1,pr)))
      else pr end if
    end proc:

    unpartProd := proc(pr, $)
    local ps, ws;
      if pr :: `*` then
        ps, ws := selectremove(q->type(q,Partition), [op(pr)]);
        if nops(ps) = 1 then
          Pmap(x->`*`(op(ws),x), unpartProd(op(1,ps)));
        else pr end if;
      else unpart(pr) end if;
    end proc;
  end module,

  isShape := kind ->
  module()
    option record;

    export MakeCtx := proc(p0,_rec)
      local p := p0, pw, p1, wps, ws, vs, cs, w, ps;
      if kind='piecewise' then
        p := Partition:-PWToPartition(p);
      end if;
      w, p1 := Partition:-Simpl:-single_nonzero_piece(p);
      if not w :: identical(true) or p1 <> p then
        [ w, p1 ]
      else
        ps := op(1, p);
        wps := map(_rec@valOf, ps);
        ws, vs, cs := map2(op, 1, wps), map2(op, 2, wps), map(condOf, ps);
        if nops(vs) > 0 and
          andmap(v->op(1,vs)=v, vs) and
          ormap(a->a<>{}, ws)
        then
          [ `bool_Or`( op( zip(`bool_And`, ws, cs) ) ) , op(1,vs) ];
        else
          [ true, p0 ];
        end if;
      end if;
    end proc;
    export MapleType := `if`(kind=`PARTITION`,'Partition','specfunc(piecewise)');
  end module,

  # convert a piecewise to a partition, which is straightforward except:
  # - if any of the branches are unreachable, they are removed
  # - if the last clause is (implicitly) `otherwise`, that clause is filled in
  #     appropriately
  # note that if the piecewise does not cover the entire domain,
  #   then this Partition will be 'invalid' (in the sense that it also
  #   will not cover the entire domain) - the 'correct' thing to do would
  #   probably be to add a new clause whose value is 'undefined'
  # the logic of this function is already essentially implemented, by KB
  # in fact, kb_piecewise does something extremely similar to this
  PWToPartition := proc(x::specfunc(piecewise))::Partition;
    # each clause evaluated under the context so far, which is the conjunction
    # of the negations of all clauses so far
    local ctx := true, n := nops(x), cls := [], cnd, ncnd, i, q, ctxC, cl;
    # handles all but the `otherwise` case if there is such a case
    for i in seq(q, q = 1 .. iquo(n, 2)) do
      cnd := op(2*i-1,x); # the clause as given
      # if this clause is unreachable, then every subsequent clause will be as well
      if ctx :: identical(false) then return PARTITION( cls );
      else
        ctxC := `And`(cnd, ctx);              # the condition, along with the context (which is implicit in pw)
        ctxC := Simpl:-condition(ctxC, _rest);

        if cnd :: `=` then ncnd := lhs(cnd) <> rhs(cnd);
        else               ncnd := Not(cnd) end if;

        ctx  := `And`(ncnd, ctx);             # the context for the next clause

        if ctx :: identical(false,[]) then    # this clause is actually unreachable
          return(PARTITION(cls));
        else
          cls := [ op(cls), op(Pieces(ctxC,[op(2*i,x)])) ];
        end if;
      end if;
    end do;

    # if there is an otherwise case, handle that.
    if n::odd then
      ctx := Simpl:-condition(ctx, _rest);
      if not ctx :: identical(false,[]) then
        cls := [ op(cls), op(Pieces(ctx,[op(n,x)])) ];
      end if;
    end if;

    if nops(cls) = 0 then
      WARNING("PWToPartition: the piecewise %1 produced an empty partition", x);
      return 0;
    end if;
    PARTITION( cls );
  end proc,

  # applies a function to the arg if arg::Partition,
  # and if arg::piecewise, then converts the piecewise to a partition,
  # applies the function, then converts back to piecewise
  # this mainly acts as a sanity check
  AppPartOrPw := proc(f,x::Or(Partition,specfunc(piecewise)))
    if x::Partition then f(x);
    else                 PartitionToPW(f(PWToPartition(x))) end if;
  end proc,

  #Check whether the conditions of a Partition depend on any of a set of names.
  ConditionsDepend:= proc(P::Partition, V::{name, list(name), set(name)}, $)
    local p;
    for p in op(1,P) do if depends(condOf(p), V) then return true end if end do;
    false
  end proc,

  # The cartesian product of two Partitions
  PProd := proc(p0::Partition,p1::Partition,{_add := `+`})::Partition;
  local ps0, ps1, cs, rs, rs0, rs1;
    ps0,ps1 := map(ps -> sort(op(1,ps), key=(z->condOf(z))), [p0,p1])[];
    cs := zip(proc(p0,p1)
                if condOf(p0)=condOf(p1) then
                  Piece(condOf(p0),_add(valOf(p0),valOf(p1))) ;
                else [p0,p1];
                end if;
              end proc, ps0,ps1);
    rs, cs := selectremove(c->type(c,list),cs);
    rs0, rs1 := map(k->map(r->op(k,r),rs),[1,2])[];
    rs := map(r0->map(r1-> Piece( bool_And(condOf(r0),condOf(r1)), _add(valOf(r0),valOf(r1)) )
                      ,rs1)[],rs0);
    PARTITION([op(cs),op(rs)]);
  end proc,

  Simpl := module()
    export ModuleApply := proc(p, $)
      local ps, qs, qs1;
      if p :: Partition then
        single_branch(remove_false_pieces(Flatten(p)));
      elif p :: `+` then
        qs := convert(p, 'list', `+`);
        ps, qs := selectremove(type, qs, Partition);
        if nops(ps)=0 then return p end if;
        ps := map(Simpl, ps);
        ps, qs1 := selectremove(type, ps, Partition);
        if nops(ps)=0 then return p end if;
        `+`(op(qs),op(qs1),foldr(Partition:-PProd,op(ps)));
      elif p :: `*` then
        qs := [op(p)];
        ps, qs := selectremove(type, qs, Partition);
        if nops(ps)=0 then return p end if;
        ps := map(Simpl, ps);
        ps, qs1 := selectremove(type, ps, Partition);
        if nops(ps)=0 then return p end if;
        `*`(op(qs),op(qs1),foldr(((a,b)->Partition:-PProd(a,b,_add=`*`)),op(ps)));
      else
        subsindets(p,{Partition,`+`,`*`},Simpl);
      end if;
    end proc;

    export single_nonzero_piece_cps := proc(k)
      local r,p; r, p := single_nonzero_piece(_rest);
      if r :: identical(true) then
        args[2]
      else
        k(r, p);
      end if;
    end proc;

    export single_nonzero_piece := proc(e, { _testzero := Testzero })
      local zs, nzs;
      if e :: Partition then
        zs, nzs := selectremove(p -> _testzero(valOf(p)), op(1, e));
        if nops(nzs) = 1 then
          return condOf(op(1,nzs)) , valOf(op(1,nzs))
        end if;
      end if;
      true, e
    end proc;

    export remove_false_pieces := proc(e::Partition, $)
      PARTITION(remove(p -> not(coulditbe(condOf(p))), op(1, e)));
    end proc;

    export single_branch := proc(e::Partition, $)
     if nops(op(1,e)) = 1 then
       op([1,1,2], e)
     else
       e
     end if;
    end proc;

    # Removal of singular points from partitions
    export singular_pts := module()
      # we can simplify the pieces which are equalities and whose LHS or
      # RHS is a name.
      local canSimp := c -> condOf(c) :: `=` and (lhs(condOf(c)) :: name or rhs(condOf(c)) :: name);

      # determines if a given variable `t' has the given upper/lower `bnd'.
      local mentions_t_hi := t -> bnd -> cl -> has(cl, t<bnd) or has(cl, bnd>t);
      local mentions_t_lo := t -> bnd -> cl -> has(cl, bnd<t) or has(cl, t>bnd);

      # replace bounds with what we would get if the equality can be
      # integrated into other pieces
      local replace_with := t -> bnd -> x ->
        if   mentions_t_hi(t)(bnd)(x) then t <= bnd
        elif mentions_t_lo(t)(bnd)(x) then t >= bnd
        else x end if;

      local set_xor := ((a,b)->(a union b) intersect (a minus b));

      # this loops over the pieces to replace, keeping a state consisting of
      # the "rest" of the pieces
      local tryReplacePieces := proc(replPieces, otherPieces,cmp,$)
        local rpp := replPieces, otp := otherPieces, nm, val, rp, rpv;
        for rp in rpp do
          rp, rpv := op(rp);
          nm   := `if`(lhs(rp)::name, lhs(rp), rhs(rp));
          val  := `if`(lhs(rp)::name, rhs(rp), lhs(rp));
          otp := tryReplacePiece( nm, val, rpv, otp, cmp )
        end do;
        otp;
      end proc;

      local do_eval_for_cmp := proc(eval_cmp, ev, x, $)
        local r;
        try
          r := eval_cmp(subs(ev,x));
        catch "numeric exception: division by zero":
          r := eval_cmp(limit(x, ev));
        end try;
        subsindets(r,And(specfunc(NewSLO:-applyintegrand),anyfunc(anything, identical(0))),_->0);
      end proc;

      local tryReplacePiece := proc(vrNm, vrVal, pc0val, pcs, eval_cmp,$)
        local pcs0 := pcs, pcs1, qs0, qs1, qs2, vrEq := vrNm=vrVal, vs2, ret, q, q_i;
        ret := [ Piece(vrEq, pc0val), op(pcs0) ] ;
        # speculatively replace the conditions
        pcs1 := subsindets(pcs0, relation, replace_with(vrNm)(vrVal));
        # convert to sets and take the "set xor", which will contain
        # only those elements which are not common to both sets.
        qs0, qs1 := seq({op(qs)},qs=(pcs0,pcs1));
        qs2 := set_xor(qs1, qs0);
        # if we have updated precisely two pieces (an upper and lower bound)
        if nops(qs2) = 2 then
          # get the values of those pieces, and the value of the
          # piece to be replaced, if that isn't undefined
          vs2 := map(valOf, qs2);
          if not pc0val :: identical('undefined') then
            vs2 := { pc0val, op(vs2) };
          end if;
          # substitute the equality over the piece values
          vs2 := map(x->do_eval_for_cmp(eval_cmp,vrEq,x), vs2);
          # if they are identically equal, return the original
          # "guess"
          if nops(vs2) = 1 then
            # arbitrarily pick the first candidate to be the one to
            # be replaced
            q := op(1,qs2);
            q_i := seq(`if`(op(i,pcs1)=q,[i],[])[],i=1..nops(pcs1));
            ret := subsop(q_i=op(q_i,pcs0), pcs1);
          end if;
        end if;
        ret;
      end proc;

      export ModuleApply := proc(p_,{eval_cmp:='value'},$)
        local p := p_, r := p, uc, oc;
        # if the partition contains case of the form `x = t', where `t' is a
        # constant (or term??) and `x' is a variable, and the value of that
        # case is `undefined', then we may be able to eliminate it (if another
        # case includes that point)
        r := op(1,r);
        uc, oc := selectremove(canSimp, r);
        PARTITION(tryReplacePieces(uc, oc, eval_cmp));
      end proc;
    end module; # singular_pts

    export condition := module()
      local is_extra_sol := x -> (x :: `=` and rhs(x)=lhs(x) and lhs(x) :: name);
      local postproc_for_solve := proc(ctx, ctxSlv)
                               ::{identical(false), list({boolean,relation,specfunc(boolean,And),`and`(boolean)})};
        local ctxC := ctxSlv;
        if ctxC = [] then
          ctxC := [] ;
        elif nops(ctxC)> 1 then
          ctxC := map(x -> postproc_for_solve(ctx, [x], _rest)[], ctxC);
        elif nops(ctxC) = 1 then
          ctxC := op(1,ctxC);
          if ctxC :: set then
            if ctxC :: identical('{}') then
              ctxC := NULL;
            else
              ctxC := remove(is_extra_sol, ctxC);
              ctxC := bool_And(op(ctxC));
            end if ;
            ctxC := [ctxC];
          elif ctxC :: specfunc('piecewise') then
            ctxC := PWToPartition(ctxC, _rest);
            ctxC := [ seq( map( o -> condOf(c) and o
                                , postproc_for_solve(ctx, valOf(c), _rest))[]
                           , c=op(1, ctxC) )] ;
          else
            ctxC := FAIL;
          end if;
        else
          ctxC := FAIL;
        end if;
        if ctxC = FAIL then
          error "don't know what to do with %1", ctxSlv;
        else
          ctxC;
        end if;
      end proc;

      export ModuleApply := proc(ctx)::list(PartitionCond);
        local ctxC := ctx;
        if ctx :: identical(true) then
          error "Simpl:-condition: don't know what to do with %1", ctxC;
        end if;
        if 'do_solve' in {_rest} then
          ctxC := solve({ctxC}, 'useassumptions'=true);
          if ctxC = NULL and indets(ctx, specfunc(`exp`)) <> {} then
            ctxC := [ctx];
          else
            ctxC := postproc_for_solve(ctx, [ctxC], _rest);
          end if;
          if indets(ctxC, specfunc({`Or`, `or`})) <> {} then
            userinfo(10, 'Simpl:-condition',
                     printf("output: \n"
                            "  %a\n\n"
                            , ctxC ));
          end if;
        else
          ctxC := Domain:-simpl_relation(ctxC, norty='DNF');
          ctxC := eval(ctxC,`And`=bool_And);
          if ctxC :: specfunc(`Or`) then
            ctxC := [op(ctxC)]
          else
            ctxC := [ctxC];
          end if;
        end if;
        ctxC;
      end proc;
    end module; #Simpl:-condition
  end module, #Simpl

  SamePartition := proc(eqCond, eqPart, p0 :: Partition, p1 :: Partition, $)
    local ps0, ps1, pc0, the;
    ps0, ps1 := seq(op(1,p),p=(p0,p1));
    if nops(ps0) <> nops(ps1) then return false end if;
    for pc0 in ps0 do
      the, ps1 :=
        selectremove(pc1 ->
          eqCond( condOf(pc1), condOf(pc0) ) and
          eqPart( valOf(pc1) , valOf(pc0)  )     ,ps1);
      if nops(the) <> 1 then
        return false;
      end if;
    end do;
    true;
  end proc
;
  uses Hakaru;
  ModuleLoad():
end module:
