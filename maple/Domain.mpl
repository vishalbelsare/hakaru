### Domain abstraction

# A domain is abstractly a pair of a "square" domain (a product of square
# domains, or an interval), the domain "bounds", and a domain "shape". The
# domain "bounds" are essentially the variables, each with the type of domain
# (Int,Sum, etc) ; the domains "shape" is sums of products of constraints
# (relations) on the domain, interspersed with 'makes' (DInto) which parametrize
# a subdomain by one of the domain variables ('picking' a particular
# parametrization of the domain, in which one variable is fixed in subsequent
# "shape" constructors).

# the seperation between the two 'stages' of domain exists mainly because
# certain simplifications need to happen after extracting the domain
# bounds but before extracting the domain shape, as the shape ends up
# becoming part of the bounds of an inner simplification.

# Note that large parts of this are not very nice. It is a very literal
# translation of the code which it replaced, which a very thin amount
# of abstraction on top. But it does the hard work of factoring
# out all of the domain-related code into a single module.
# At some point, the interface should be improved, and the implementation
# should get rid of all sorts of unnecessary conversions.
Domain := module()

option package;

    global DOMAIN;
    global DBound;

    global DConstrain;
    global DSum;
    global DSplit;
    global DInto;

    global DNoSol;

    # Checks if an expression has domain bounds/shape, and check for either one.
    export Has := module ()

       export Bound := proc(e, $)::truefalse;
               assigned(Domain:-ExtBound[op(0,e)]) and
               evalb(e :: Domain:-ExtBound[op(0,e)]:-MapleType);
       end proc;

       export Shape := proc(e, $)::truefalse;
               assigned(Domain:-ExtShape[op(0,e)]) and
               evalb(e :: Domain:-ExtShape[op(0,e)]:-MapleType);
       end proc;

       export ModuleApply := proc(e, $)::truefalse;
               Bound(e) or Shape(e);
       end proc;

    end module;

    # Convert Domain to a KB. Very partial, mainly for backwards compatibility
    # for parts of the code which still work with KB.
    export Bound := module ()

       export toKB := proc(dom :: DomBound, kb0 :: t_kb, $)::[t_kb_mb, list(name=name)];
         local kb := kb0, vs := op(1, dom), rn := []
             , vn, vt, make, lo, hi, vn_rn, rn_t, v ;

         for v in vs do
             vn, vt, make := op(v);
             lo, hi := ExtBound[make]:-SplitBound(vt);
             vn_rn, kb := ExtBound[make]:-MakeKB( vn, lo, hi, kb );

             rn := [ vn=vn_rn, op(rn) ];
         end do;

         [ kb, rn ]
       end proc;

       export varsOf := proc(dom :: DomBound, $)::list(name);
         map(x->op(1,x), op(1, dom));
       end proc;

       export get := proc(dom :: DomBound, var :: name, $)
         local th;
         th := select(x->op(1,x)=var, op(1,dom));
         if nops(th) = 1 then
             op([1,2], th), op([1,3], th)
         elif nops(th) = 0 then
             error "cannot find var %1 in %2", var, dom;
         else
             error "multiple references in %1", dom;
         end if;

       end proc;

       local constrain := proc( opts, vn::name, ty::range, mk :: DomBoundKind, $ )
                       :: set({relation, `::`});
                  local lo, hi, noi, bt
                      , noinf := evalb('no_infinity' in opts)
                      , btys  := evalb('bound_types' in opts)
                      ;

                  lo,hi := Domain:-ExtBound[mk]:-SplitBound(ty);
                  noi := `if`(noinf,mk->b->if b in {infinity,-infinity} then {} else {mk(b)} end if
                                   ,mk->b->{mk(b)} );

                  bt  := `if`(btys, { vn :: Domain:-ExtBound[mk]:-BoundType }, {});

                  { noi(x->Domain:-ExtBound[mk]:-Constrain( x, vn ))(lo)[]
                  , noi(x->Domain:-ExtBound[mk]:-Constrain( vn, x ))(hi)[]
                  , bt[]
                  }
       end proc;

       local toConstraints_opts := { 'no_infinity', 'bound_types' };

       export toConstraints := proc( bnd :: DomBound )
                  local cs, opts, bad_opts, noinf;
                  opts := { args[2..-1] } ;
                  bad_opts := opts minus toConstraints_opts;
                  if bad_opts <> {} then
                      error "invalid arguments: %1", bad_opts;
                  end if;

                  cs := {op(map(b->constrain(opts, op(b))[], op(1,bnd)))};
                  cs;
       end proc;

    end module;

    export Shape := module ()

         export asConstraints := proc(sh_ :: DomShape, $)::list({boolean,relation,specfunc(`Or`)});
           local sh := sh_;

           if sh :: specfunc(`DConstrain`) then
               [ op(sh) ];

           elif sh :: specfunc(`DSum`) then
               sh := Or(op(map(x->And(op(asConstraints(x))), sh)));
               sh := Domain:-simpl_relation({sh}, norty='CNF');

               sh := map(x->Or(op(x)),sh);

               sh;

           # elif sh :: specfunc(`DSplit`) then

           elif sh :: specfunc(`DInto`) then
               asConstraints(op(3, sh));
           else
               error "don't know how to convert to constraints %1", sh
           end if;

         end proc;

    end module;

    # Domain types which are registered/unregistered with TypeTools.
    # Note that the types have to be quoted (additionally to the quote one would
    # normally place on certain types) to work properly
    local DomainTypes := table(
           # Domain bounds
           [(DomBoundBinder = ''DInto(name, range, DomBoundKind)'' )
           ,(DomBoundKind   = 'And(name, satisfies(nm->assigned(Domain:-ExtBound[nm])))' )

           ,(DomBound       = ''DBound(list(DomBoundBinder))'' )

           # Domain shape
           ,(DomConstrain = 'specfunc(relation, `DConstrain`)' )
           ,(DomSum       = 'specfunc(DomShape, `DSum`)' )
           ,(DomSplit     = ''DSplit(Partition(DomShape))'' )
           ,(DomInto      = ''DInto(name, range, DomShape)'' )
           ,(DomShape     = 'Or( DomConstrain, DomSum, DomSplit, DomInto )' )

           # Domain
           ,(HDomain = ''DOMAIN(DomBound, DomShape)'' )

           # Maybe domain
           ,(DomNoSol  = 'specfunc(`DNoSol`)' )
           ,(HDomain_mb = ''Or(HDomain, DomNoSol)'' )
           ] );


    # Extending domain extraction and replacement.
    export ExtBound := table();
    export ExtShape := table();

    local ModuleLoad := proc($)
           local ty_nm;

           for ty_nm in [ indices(DomainTypes, nolist) ] do
               TypeTools[AddType]( ty_nm, DomainTypes[ty_nm] );
           end do;

           unprotect(Domain:-ExtBound);
           ExtBound[`Int`] :=
               Record('MakeKB'=KB:-genLebesgue
                     ,'ExtractVar'=(e->op(1,e))
                     ,'ExtractBound'=(e->op(2,e))
                     ,'SplitBound'=(e->op(e))
                     ,'Constrain'=`<`
                     ,'MakeEqn'=`=`
                     ,'MapleType'='And(specfunc({Int}), anyfunc(anything,name=range))'
                     ,'BoundType'='real'
                     );

           ExtBound[`Sum`] :=
               Record('MakeKB'=KB:-genSummation
                     ,'ExtractVar'=(e->op(1,e))
                     ,'ExtractBound'=(e->op(2,e))
                     ,'SplitBound'=(e->op(e))
                     ,'Constrain'=`<=`
                     ,'MakeEqn'=`=`
                     ,'MapleType'='And(specfunc({Sum}), anyfunc(anything,name=range))'
                     ,'BoundType'='integer'
                     );
           protect(Domain:-ExtBound);

           unprotect(Domain:-ExtShape);

           ExtShape[`Indicator`] :=
               Record('MakeCtx'=(e -> [ op(1,e), 1 ] )
                     ,'MapleType'='Indicator(anything)'
                     );

           ExtShape[`PARTITION`] :=
               Record('MakeCtx'=
                      (proc(p0,$)
                           local p := p0, pw, wps, ws, vs, cs, w, ps;
                           w, p := Partition:-Simpl:-single_nonzero_piece(p);
                           if w <> {} then
                               [ `and`(op(w)), p ]
                           else
                               ps := op(1, p);
                               wps := map(x->Domain:-Extract:-Shape(valOf(x), 'no_simpl'), ps);
                               ws, vs, cs := map2(op, 1, wps), map2(op, 2, wps), map(condOf, ps);

                               if nops(vs) > 0 and
                                  andmap(v->op(1,vs)=v, vs) and
                                  ormap(a->a<>{}, ws)
                               then
                                   [ `Or`( op( zip(`And`, ws, cs) ) ) , op(1,vs) ];
                               else
                                   [ true, p0 ];
                               end if;
                           end if;
                       end proc)
                     ,'MapleType'='Partition'
                     );

           ExtShape[`piecewise`] :=
               Record('MakeCtx'=
                       (proc(p, $)
                         local w, pw1;
                         w, p1 := Domain:-ExtShape[`PARTITION`]:-MakeCtx( PWToPartition(p) ) [] ;
                         if w = true then
                             [ true, p ] ;
                         else
                             [ w, p1 ];
                         end if;
                        end proc)
                     ,'MapleType'=specfunc(`piecewise`)
                     );

           unprotect(Domain:-ExtShape);
    end proc;

    local ModuleUnload := proc($)
        local ty_nm;
        for ty_nm in [ indices(DomainTypes, nolist) ] do
            if TypeTools[Exists](ty_nm) then TypeTools[RemoveType](ty_nm) end if;
        end do;

    end proc;

    # Extract a domain from an expression
    export Extract := module ()

           # Extract a domain bound from an expression
           # This pops off the integration constructors recursively, keeping
           # track of the bounds in a KB (which literally become the DBound).
           export Bound := module ()
             local do_extract_arg := proc(vars, kind, arg_, bound, $)
               local x0, x, vars1, arg := arg_, rng;

               x0  := ExtBound[kind]:-ExtractVar(bound);   # variable name
               rng := ExtBound[kind]:-ExtractBound(bound); # variable range
               x   := DInto(x0, rng, kind);                # the variable spec
               vars1 := [ x, op(vars) ];

               do_extract(vars1, arg);
             end proc;

             local do_extract := proc(vars, arg, $)
               if Domain:-Has:-Bound(arg) then
                   do_extract_arg(vars, op(0,arg), op(arg));
               else
                   arg, vars
               end if;

             end proc;

             export ModuleApply := proc(e, $) :: [ DomBound, anything ];
                        local arg, vars, kb;
                        arg, vars := do_extract([], e);

                        [ DBound(vars), arg ];
             end proc;
           end module;


           # Extract a domain shape from an expression
           # This extracts the domain shape from individual multiplicands of
           # expressions, and multiplies the subexpressions back together.
           # essentially this assumes a distributive law (of domain shapes over
           # products)
           export Shape := module ()

             local do_get := proc(f, f_ty, e, $)
               local sub, inds, rest;
               if e::`*` then
                 sub := map(x->do_get(f, f_ty,x), [op(e)]);
                 [ `And`(op(map2(op,1,sub))), `*`(op(map2(op,2,sub))) ]
               elif e::`^` then
                 inds, rest := do_get(f, f_ty, op(1,e)) [] ;
                 [ inds, subsop(1=rest, e) ]
               elif e:: f_ty then
                 f(e)
               else
                 [ true, e ]
               end if

             end proc;

             # apply a list of extractors, in order, until all fail to produce
             # any output .
             local do_gets := proc(todo::list, w, e, $)
                       local t0, ts, w1, e1;
                       if nops(todo) = 0 then
                           [ w, e ]
                       else
                           t0 := op(1, todo);
                           ts := op(subsop(1=NULL, todo));
                           if indets(e, specfunc(t0)) <> {} then
                               w1, e1 :=
                                 do_get(ExtShape[t0]:-MakeCtx
                                       ,ExtShape[t0]:-MapleType
                                       ,e) [] ;
                               ts := `if`(is(w1), [ts], [ts, t0]);

                               do_gets( ts, And(w1, w), e1 );
                           else
                               do_gets( [ ts ], w, e );
                           end if;
                       end if;
             end proc;

             # todo: simplify the shape
             local simpl_shape := proc(e0,ctx,$)
                local e := Domain:-simpl_relation({e0});

                e := subsindets(e, set , x->DSum(op(x)));
                e := subsindets(e, list, x->DConstrain(op(x), op(ctx)));
                e;
             end proc;

             export ModuleApply := proc(e, { ctx := KB:-empty }) :: [ anything, anything ];
                        local ixs, w, e1, ctx1;
                        ixs := [indices(ExtShape, 'nolist')];
                        w, e1 := do_gets(ixs, true, e) [];

                        if not ('no_simpl' in {_rest}) then
                            ctx1 := KB:-kb_to_constraints(ctx);
                            w := simpl_shape(w, ctx1);
                        end if;

                        [ w, e1 ];
             end proc;
           end module;

           export ModuleApply := proc(e, { ctx := KB:-empty }, $) :: [ HDomain, anything ];
                      local b, eb, s, es;
                      b, eb := op(Bound(e));
                      s, es := op(Shape(eb, ctx=ctx ));
                      [ DOMAIN(b, s), es ];
           end proc;
    end module;


    # Apply a domain to an expression.
    # Apply will perform certain 'simplifications' to make sure the
    # domain application is well-formed. e.g.,
    #   DOMAIN( DBound( [x,y], [xt,yt] ), DConstrain(..) )
    #      is the same as
    #   DOMAIN(        ..               , DInto(x,xt,DInto(y,yt,DConstrain(..))) )
    # basically, when we see an 'unbound' variable in the 'RHS' , we should bind
    # it with the default 'DInto'.

    export Apply := module ()
           local do_mk := proc(e, vn, ty_, mk, $)
              mk(e, Domain:-ExtBound[mk]:-MakeEqn(vn, ty_));
           end proc;

           # main loop of the apply function
           # e     := expr
           # vs    := variables
           # vs_ty := domain bounds (as a kb)
           # sh    := domain shape
           local do_apply := proc(done__, e, vs, sh_, $)
              local sh := sh_, done_ := done__
                  , cond, r, vs_td, v_td, vn_td, vt_td, vt_mk, vn, vt, shv, vars, deps
                  , e1, v, vvn, vvt, vmk,  with_kb1 ;

              # If the solution is a constraint, and the constraint is true,
              # then just produce the expression. If it isn't necessarily true
              # (i.e. trivial) then produce a Partition with the constraint as a
              # guard.
              if sh :: DomConstrain then
                  cond := `and`(op(sh));
                  if is(cond) then
                      r := e
                  else
                      r := PWToPartition(piecewise(cond, e, 0));
                  end if;

                  # if there are still integrals which have not been applied,
                  # apply them now
                  vs_td := select(x -> not(op(1, x) in done_), op(1, vs));
                  for v_td in vs_td do
                      vn_td, vt_td, vt_mk := op(v_td);
                      r := do_mk(r, vn_td, vt_td, vt_mk);
                  end do;

                  r;

              # if the solution is a sum of solutions, produce the algebraic sum
              # of each summand of the solution applied to the expression.
              elif sh :: DomSum then
                  `+`(seq(do_apply(done_, e, vs, s), s=sh))

              # if the solution is a split solution, just make `do_apply' over
              # the values of the Partition (the subsolutions)
              elif sh :: DomSplit then
                  sh := op(1, sh);
                  Partition:-Pmap(p-> do_apply(done_, e, vs, p), sh);

              # performs the 'make' on the expression after recursively
              # applying the solution
              elif sh :: DomInto then
                  # deconstruction
                  vn, vt, shv := op(sh);

                  # extract bounds which have not been applied upon which this
                  # bound depends. Those are applied after this one, so are not
                  # in 'scope' in the recursive call
                  vars := {op(Domain:-Bound:-varsOf(vs))};
                  deps := (indets(vt, name) intersect vars) minus done_ ;
                  done_ := `union`(done_, deps, {vn}) ;

                  # recursively apply
                  e1 := do_apply(done_, e, vs, shv);

                  # build this integral, and the other this one depended on
                  for v in op(1,vs) do
                      vvn, vvt, vmk := op(v);
                      if vvn in deps then
                          e1 := do_mk(e1, vvn, vvt, vmk);
                      elif vvn = vn then
                          e1 := do_mk(e1, vvn,  vt, vmk);
                      end if;
                  end do;

                  e1;

              else
                  error "don't know how to apply %1", sh
              end if;
           end proc;

           export ModuleApply := proc(dom :: HDomain_mb, e, $)
             local vs, sh;
             if dom :: DomNoSol then
                 error "cannot apply %1", dom;
             end if;

             vs, sh := op(dom);

             do_apply({}, e, vs, sh);
           end proc;

           export Shape := proc(dsh :: DomShape, e, $) ModuleApply( DOMAIN( [], dsh ), e ) end proc;

           export Bound := proc(dbn :: DomBound, e, $) ModuleApply( DOMAIN( dbn, DConstrain() ), e ) end proc;

    end module;

    export Improve := module ()
           export Simplifiers := table();

           export ModuleLoad := proc($)

             Simplifiers[`Obviously redundant 'DInto's`] :=
                 Record('Order'=2
                       ,'DO'=(proc(dom, $)
                                  local vs, sh;
                                  vs, sh := op(dom);
                                  # This 'simplification' removes redundant information, but it is
                                  # entirely pointless as the result should be the same anyways. This
                                  # is mainly here as an assertion that Apply properly
                                  # re-applies integrals when the domain shape does not explicitly
                                  # state them.
                                  sh := subsindets( sh, DomInto
                                                  , proc (x, $)
                                                        local x_vn, x_t0, x_rest, x_t, x_mk;
                                                        x_vn, x_t0, x_rest := op(x);
                                                        x_t, x_mk := Domain:-Bound:-get(vs, x_vn);
                                                        if x_t = x_t0 then
                                                            x_rest
                                                        else
                                                            x
                                                        end if;
                                                   end proc );

                                  DOMAIN(vs, sh);

                              end proc)
                        );


             Simplifiers[`Make constraints abouts vars`] :=
                 Record('Order'=6
                       ,'DO'=
                   (module()

                    export ModuleApply := proc(dom, $)
                               local vs, sh, vars, ctx_vs;
                               vs, sh := op(dom);
                               vars := {op(Domain:-Bound:-varsOf(vs))};
                               ctx_vs := Domain:-Bound:-toConstraints(vs, 'bound_types');

                               sh := subsindets(sh, DomConstrain, x->do_simpl_constraints(vars, ctx_vs, x));
                               DOMAIN(vs, sh);
                    end proc;

                    local do_simpl_constraints := proc(vars, ctx_vs, x, $)
                              local ctx1, ctx, ss, td, rest, d;
                              ss, ctx := selectremove(q->depends(q,vars), x);

                              td, rest := selectremove(type, ss
                                                       , And(relation
                                                             ,satisfies(
                                                                 q-> not(lhs(q) in vars) and not(rhs(q) in vars)
                                                                       )
                                                            )
                                                      );

                              ctx1 := { op(ctx), op(ctx_vs), op(rest) };

                              d := map(x->try_make_about(vars,ctx1,x), td);

                              DConstrain(op(d), op(ctx), op(rest));

                    end proc;

                    local try_make_about := proc(vars, ctx1, q0, $)
                              local vars_q, q_s, q := q0;
                              vars_q := indets(q, name) intersect vars;
                              if nops(vars_q) = 1 then
                                  vars_q := op(1,vars_q);

                                  q := KB:-try_improve_exp(q, vars_q, ctx1);

                                  try
                                      q_s := solve({q},[vars_q], 'useassumptions'=true)
                                               assuming (op(ctx1));

                                  catch "when calling '%1'. Received: 'numeric exception: underflow'":
                                      return q

                                  end try;

                                  if q_s::list and nops(q_s)=1 then
                                      op(op(1,q_s));
                                  else
                                      q
                                  end if;

                              else
                                  q
                              end if;
                    end proc;

                    end module));

             Simplifiers[`LMS`] := Record('Order'=10,'DO'=(
                 module()

                   local countVs := vs -> (c-> nops(indets(c, name) intersect {op(vs)} ));

                   # Sorts the solutions so that resulting integrals are
                   # well-scoped
                   local orderSols := proc(sol,vs,$)
                     local sol2, solOrder ;

                     # sort the conjs by the number of variables which they mention
                     sol2, solOrder :=
                               sort( sol, key= (x-> -(countVs(vs)(x)))
                                   , output=[sorted,permutation]
                                   );

                   end proc;

                   # given a solution for a single variable,
                   # either extracts upper and/or lower bounds from the solution
                   # or leaves that solution as a constraint.
                   local classifySol1 :=
                     proc(sol :: set({relation,boolean}), v, ctx, $)
                         local hi, lo, v_t;

                         # try to check if we can extract upper and lower bounds from the
                         # solution directly
                         hi := subsindets( sol , {relation,boolean} , extract_bound_hi(v) );
                         lo := subsindets( sol , {relation,boolean} , extract_bound_lo(v) );

                         if `and`(nops(sol) = 2
                                 ,nops(hi) = 1
                                 ,nops(lo) = 1
                                 ) then
                             v_t := op(1,lo) .. op(1,hi) ;

                             DInto(v, v_t, ctx);

                         elif nops(sol) = 1 and (nops(hi) = 1 or nops(lo) = 1) then
                             lo := `if`( nops(lo) = 1 , op(1,lo), -infinity );
                             hi := `if`( nops(hi) = 1 , op(1,hi),  infinity );

                             v_t := lo .. hi;

                             DInto(v, v_t, ctx);

                         else
                             subsindets( ctx, DomConstrain
                                       , x-> DConstrain(op(x), op(sol))
                                       );
                         end if;
                 end proc;

                 # Orders the solution, then classifies each solution, and
                 # builds the single solution with the correct variable order.
                 local classifySols := proc(vs, vs_ty, $) proc( sol :: list(set({relation,boolean})), $ )
                    local sol1, ctx, dmk, s, solOrd, vso, v;
                    sol1, solOrd := orderSols(sol, vs);
                    vso := vs[solOrd];

                    sol1 := zip(proc() [_passed] end proc, sol1, vso);

                    ctx := DConstrain();
                    for v in sol1 do
                        ctx := classifySol1(op(v), ctx);
                    end do;

                    ctx;
                 end proc; end proc;

                 # transforms the solution to the form required by Domain
                 # this would be a straightforward syntactic manipulation,
                 # but for the facts that we have to:
                 #  decide the order of integration
                 #  decide which solutions become integrations and which
                 #     become constrains
                 local postproc := proc(sol, ctx, vs, $)
                   local ret := sol;

                   ret := subsindets(ret, specfunc('piecewise')
                                    , x-> DSplit(Partition:-PWToPartition(x)));

                   ret := subsindets(ret
                                    , Or(identical({}), set(list))
                                    , x -> DSum(op(x)) );

                   # vs := Domain:-Bound:-varsOf(ctx);

                 # `true' (produced by LMS for trivial systems) - to the
                 #    interval for the variable corresponding to this index in
                 #    the sequence.
                 # `c : name' - to the interval for `v'
                 # everything else - to itself
                   ret := subsindets(ret, list(set({relation,boolean, name}))
                                    , classifySols(vs, ctx) @
                                      (ls->map(si->remove(x->x::identical(true) or x::name, si), ls))
                                     );

                   ret;
                 end proc;

                 # Note this will not simplify solutions, in the sense that if
                 # there are multiple places to apply LMS, the resulting
                 # solution after applying LMS is not simplified any
                 # further. This should probably be done by a seperate
                 # simplifier.
                 local do_LMS := proc( sh :: DomShape, ctx :: DomBound, vs, $)
                    local sol;
                    if sh :: DomConstrain then
                        sol := do_LMS_Constrain(sh, ctx, vs);
                        if sol :: DomShape then
                            sol
                        else
                            postproc(sol, ctx, vs);
                        end if;

                    elif sh :: DomSplit then
                        # todo: incorporate piece condition into context
                        DSplit( Partition:-Pmap(p->do_LMS(p, ctx, vs), op(1, sh)) );

                    elif sh :: DomSum then
                        map(s->do_LMS(s, ctx, vs), sh);

                    else
                        DNoSol(sprintf("Don't know how to solve DOMAIN(%a, %a)", ctx, sh));
                    end if;
                 end proc;

                 # ask Maple for a solution to our system
                 local do_LMS_Constrain := proc( sh :: DomConstrain , ctx, vs_, $ )
                   local vs := vs_
                       , cs, do_rn, ret;

                   cs := { op( Domain:-Bound:-toConstraints(ctx,'no_infinity') )
                         , op(sh)
                         } ;

                   # there are variables to solve for, but no non-trivial
                   # constraints which need to be solved.
                   if cs = {} and not vs = [] then
                     # this matches the output format of LMS; [x,y] -> { [ {true}, {true} ] }
                     ret := { map(o->{true}, vs) };

                   elif not cs = {} and vs = [] then
                       ret := DNoSol("There are no variables to solve for, but there are constraints."
                                   " This means the variables have not been correctly identified.");

                   elif cs = {} and vs = [] then
                       ret := DNoSol("Something went very wrong");

                   else
                       try
                           ret := LinearMultivariateSystem( cs, vs );
                       catch "the system must be linear in %1":
                           ret := DNoSol(sprintf("The system (%a) must be linear in %a."
                                                , cs, vs ));

                       catch "inequality must be linear in %1":
                           ret := DNoSol(sprintf("The system (%a) contains nonlinear inequality in "
                                                "one of %a."
                                                , cs, vs ));
                       end try;

                   end if;

                   ret;
                 end proc;

                 export ModuleApply := proc(dom :: HDomain, $) :: HDomain_mb;
                    local dbnds, dshape, sol, res, errs, vs;
                    dbnds, dshape := op(dom);
                    vs := Domain:-Bound:-varsOf(dbnds);

                    # We use the opposite "integration order" than LMS, so
                    # reverse the variables. The scare quotes are because LMS
                    # knows nothing about domains or integration, but it does
                    # try to place the first variable "outermost" (probably
                    # because it solves for each variable one by one, at starts
                    # at the left) which will flip things around for no reason.
                    vs := ListTools[Reverse](vs);

                    sol := do_LMS( dshape , dbnds, vs );

                    errs := indets(sol, DomNoSol);
                    if errs <> {} then return DNoSol(seq(op(e), e=errs)) end if;

                    DOMAIN( dbnds, sol );

                 end proc;

                 end module));

           end proc;

           local combine_errs := proc(e0 :: DomNoSol, e1 :: DomNoSol, $) :: DomNoSol;
              DNoSol( op(e0), op(e1) );
           end proc;


           # TODO: this should keep errors (esp. if everything fails to
           # simplify), or print them as a warning(?)
           local cmp_simp := proc(s0, s1, $) proc(dom :: HDomain_mb , $)
                                                 ::HDomain_mb;
              local dom1 := s0(dom), r;
              if not dom1 :: DomNoSol then
                  s1(dom1);
              else
                  r := s1(dom);
                  if r :: DomNoSol then
                      r := combine_errs( dom1, r );
                  end if;
                  r
              end if;
           end proc; end proc;

           export ModuleApply := proc(dom :: HDomain, $)::HDomain_mb;
               local es := [ seq( Simplifiers[si]:-DO
                                 , si=sort( [indices(Simplifiers,nolist)]
                                          , key=(si->Simplifiers[si]:-Order)
                                          )
                                ) ]
                   , mk := foldr( cmp_simp , (_->_), op(es) );
               mk(dom);
           end proc;
    end module;



    export simpl_relation :=
    proc( expr_ :: set({relation, boolean, specfunc({`And`,`Not`,`Or`}), `and`, `not`, `or`})
        , { norty := 'DNF' }
        , $) :: { set(list({relation, specfunc(relation, Not)}))
                , list(set({relation, specfunc(relation, Not)}))
                };

        local expr := expr_, outty, outmk, inty, inmk ;

        # simplify negations of relations
        expr := subsindets(expr, { specfunc(relation, `Not`), `not`(relation) }
                          , x-> KB:-negate_rel(op(1,x))
                          );

        expr := subsindets(expr, { specfunc(`Not`), `not` }
                          , x->Logic:-`&not`(op(1,x))
                          ) ;

        expr := subsindets(expr, { specfunc(`Or`), `or` }
                          , x->Logic:-`&or`(op(x))
                          ) ;

        expr := subsindets(expr, { specfunc(`And`), `and` }
                          , x->Logic:-`&and`(op(x))
                          ) ;

        expr := Logic:-`&and`(op(expr));

        expr := Logic:-Normalize(expr, form=norty);

        expr := subsindets(expr, specfunc(Logic:-`&and`), x->[op(x)]);
        expr := subsindets(expr, specfunc(Logic:-`&or`) , x->{op(x)});
        expr := subsindets(expr, specfunc(Logic:-`&not`), x->KB:-negate_rel(op(1,x)) );

        if expr :: identical(false) then
            return `if`(norty='DNF', {}, [{}]);
        elif expr :: identical(true) then
            return `if`(norty='DNF', {[]}, []);
        end if;

        if norty = 'DNF' then
            outty := 'set'; outmk := (x->{x});
            inty  := 'list'; inmk := (x->[x]);
        else
            outty := 'list'; outmk := (x->[x]);
            inty  := 'set'; inmk := (x->{x});
        end if;

        if not expr :: outty then expr := outmk(expr) end if;
        expr := map(x -> if not x :: inty then inmk(x) else x end if, expr);
        expr;
    end proc;

    uses Hakaru, Partition, SolveTools[Inequality] ;

end module;