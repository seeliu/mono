//
// jscript-lexer-parser.g: EcmaScript Grammar written on antlr.
//
// Author:
//	 Cesar Lopez Nataren (cesar@ciencias.unam.mx)
//
// (C) 2003, Cesar Lopez Nataren
//

options {
	language = "CSharp";
	namespace = "Microsoft.JScript";
}

//
// Parser
//

class JScriptParser extends Parser;
options {
	defaultErrorHandler = false;
}

program returns [ScriptBlock prog]
{ prog = new ScriptBlock (); }
	: source_elements [prog.src_elems]
	;

source_elements [Block elems]
	: (source_element [elems, elems.parent])*
	;

source_element [Block elems, AST parent]
{ AST stm = null; }
	: stm = statement [parent]
	  { 
		  if (stm != null) {
		  	  elems.Add (stm); 
		  	  Console.WriteLine ("DEBUG::src_elem::Add::{0}", 
					     stm.ToString ());
		  }
	  }
	| stm = function_decl_or_expr [parent]
          {
		  if (stm != null)
			  elems.Add (stm);
			  Console.WriteLine ("DEBUG:src_elem::Add (function)");
	  }
	;

function_decl_or_expr [AST parent] returns [AST func]
{
	func = null;
	bool is_func_exp = false;
	FormalParameterList p = null;
	Block body = null;
}
	: "function" (id:IDENTIFIER | { is_func_exp = true; } ) 
	  OPEN_PARENS (p = formal_param_list | ) CLOSE_PARENS 
	  (COLON type_annot:IDENTIFIER | )
	  {
		if (is_func_exp)
			if (type_annot == null)
				func = new FunctionExpression (parent, String.Empty, p,
							       null, null);
			else 
				func = new FunctionExpression (parent, String.Empty, p,
							       type_annot.getText (), null);
		else if (type_annot == null)
			func = new FunctionDeclaration (parent, id.getText (), p, null, null);
		     else 
			func = new FunctionDeclaration (parent, id.getText (), p, 
							type_annot.getText (), null);
	  }
	  OPEN_BRACE 
		  body = function_body [func] 
		  { ((FunctionDeclaration) func).Function.body = body; } 
	  CLOSE_BRACE
	;

function_body [AST parent] returns [Block elems]
{
	elems = new Block (parent);
}
	: source_elements [elems]
	;

formal_param_list returns [FormalParameterList p]
{
	p = new FormalParameterList ();
}
	: i:IDENTIFIER (COLON t1:IDENTIFIER { p.Add (i.getText (), t1.getText ()); } 
		       | { p.Add (i.getText (), "Object"); } 
		       )
	  (COMMA g:IDENTIFIER (COLON t2:IDENTIFIER { p.Add (g.getText (), t2.getText ()); } 
			      | { p.Add (g.getText (), "Object"); }
			      )
	  )*
	;

//
// Statements
//

statement [AST parent] returns [AST stm]
{ stm = null; }
	: stm = expr_stm [parent] SEMI_COLON
	| stm = var_stm [parent]
	| empty_stm
	| stm = if_stm [parent]
	| iteration_stm [parent]
	| stm = continue_stm
	| stm = break_stm
	| stm = return_stm [parent]
	| stm = with_stm [parent]
	| switch_stm [parent]
	| stm = throw_stm [parent]
	| try_stm
	;

block
	: OPEN_BRACE (statement [null])* CLOSE_BRACE
	;

try_stm
	: "try" block
	  ((catch_exp (finally_exp | ) | ) | finally_exp)
	;

catch_exp
	: "catch" OPEN_PARENS IDENTIFIER CLOSE_PARENS block
	;

finally_exp
	: "finally" block
	;

throw_stm [AST parent] returns [AST t]
{
	t = null;
	AST e = null;
}
	: "throw" e = expr [parent] SEMI_COLON
	  {
		  t = new Throw (e);
	  }
	;

switch_stm [AST parent]
	: "switch"  OPEN_PARENS expr [parent] CLOSE_PARENS case_block
	;

case_block
	: OPEN_BRACE case_clauses  default_clause case_clauses CLOSE_BRACE
	;

default_clause
	: "default" COLON statement_list
	;

case_clauses
	: (case_clause)*
	;

case_clause
	: "case" expr [null] COLON statement_list
	;

with_stm [AST parent] returns [AST with]
{
	with = null;
	AST exp, stm;
	exp = stm = null;
}
	: "with" OPEN_PARENS exp = expr [parent] CLOSE_PARENS stm = statement [null]
	  {
		  with = new With (exp, stm);  
	  }	
	;

return_stm [AST parent] returns [AST r]
{
	r = null;
	AST e = null;
}
	: "return" (e = expr [parent] { r = new Return (e); } | ) SEMI_COLON
	;

break_stm returns [AST b]
{
	b = new Break ();
}
	: "break" ( id:IDENTIFIER
		    { ((Break) b).identifier = id.getText (); }
		  | { ((Break) b).identifier = String.Empty; } ) SEMI_COLON
	;
	
continue_stm returns [AST cont]
{ cont = new Continue (); }
	: "continue" ( id:IDENTIFIER 
	               { ((Continue) cont).identifier = id.getText (); } 
	             | { ((Continue) cont).identifier = String.Empty; } ) SEMI_COLON
	;

iteration_stm [AST parent]
	: "do" statement [null] "while" OPEN_PARENS expr [parent] CLOSE_PARENS SEMI_COLON
	| "while" OPEN_PARENS expr [parent] CLOSE_PARENS statement [null]
	| "for" OPEN_PARENS inside_for [parent] CLOSE_PARENS statement [null]
	;

inside_for [AST parent]
	// We must check the NoIn restriction
	: (expr [parent] | ) SEMI_COLON (expr [parent] | ) SEMI_COLON (expr [parent] | )
	// We must keep a counter c, c tells us how many decls are
	// done, in order to interrupt if c > 1 and we are inside a "in"
	| "var" (var_decl_list [null, null] 
		  ( SEMI_COLON (expr [parent] | ) SEMI_COLON (expr [parent] | )
		  | "in" expr [parent]))
	// FIXME: left_hand_side_expr in exp rule, missing
	;

if_stm [AST parent] returns [AST ifStm]
{
	ifStm = null;
	AST cond, true_stm, false_stm;
	cond = true_stm = false_stm = null;
}
	: "if" OPEN_PARENS cond = expr [parent] CLOSE_PARENS true_stm = statement [null]
	  (("else")=> "else" false_stm = statement [null] | )
	  {
		  ifStm = new If (cond, true_stm, false_stm);
	  }
	;

empty_stm
	: SEMI_COLON
	;

var_stm [AST parent] returns [VariableStatement var_stm]
{ var_stm = new VariableStatement (); }
	: "var" var_decl_list [var_stm, parent] SEMI_COLON
	;

var_decl_list [VariableStatement var_stm, AST parent]
{ VariableDeclaration var_decln = null; }
	: var_decln = var_decl [parent]
	  { 
		if (var_decln != null)
			var_stm.Add (var_decln);
	  }
	  (COMMA var_decln = var_decl [parent]
	  { 
		  if (var_decln != null) 
		  	  var_stm.Add (var_decln);
	  }
	  )*
	;
	

var_decl [AST parent] returns [VariableDeclaration var_decl]
{ 
	var_decl = null;
	AST init = null;
}
	: id:IDENTIFIER (COLON type_annot:IDENTIFIER | )
	  (init = initializer [parent]
	   { 
		  if (type_annot == null)
		  	  var_decl = new VariableDeclaration (parent, id.getText (), null , init);
		  else 
			  var_decl = new VariableDeclaration (parent, id.getText (), type_annot.getText () , init); 
	   }
	  | 
	   {
		  if (type_annot == null)
			  var_decl = new VariableDeclaration (parent, id.getText (), null, null);
		  else
			  var_decl = new VariableDeclaration (parent, id.getText (), type_annot.getText (), null);
	   })
	;

initializer [AST parent] returns [AST init]
{ init = null; }
	: ASSIGN init = assignment_expr [parent]
	;

expr_stm [AST parent] returns [AST e]
{ e = null; }
	: e = expr [parent]
   	;


statement_list
	: (statement [null])*
	;

expr [AST parent] returns [Expression e]
{
	e = new Expression ();
	AST a = null;
} 
	: a = assignment_expr [parent] { e.Add (a); } 
	  (COMMA a = assignment_expr [parent] { e.Add (a); } )*
	;
assignment_expr [AST parent] returns [AST assign_expr]
{     
	assign_expr = null;
	JSToken op = JSToken.None;
	AST left, right;
	left = right = null;
}
	: ((left_hand_side_expr [parent] assignment_op)=> 
	    left = left_hand_side_expr [parent] op = assignment_op right = assignment_expr [parent]
	    {
		  Binary a = new Binary (parent, left, right, op);
		  Console.WriteLine ("\nDEBUG::jscript.g::assign_expr::ToString::" + a.ToString () + "\n");
		  assign_expr = a;
	    }
 
	| assign_expr = cond_expr [parent]
	)
	;

member_expr [AST parent] returns [AST mem_exp]
{
	mem_exp = null;
}
	: mem_exp = primary_expr [parent] member_aux [parent]
	| "new" member_expr [parent] arguments [parent]
	;

member_aux [AST parent]
	: ( DOT IDENTIFIER member_aux [parent]
	  | (OPEN_BRACKET)=> OPEN_BRACKET expr [parent] CLOSE_BRACKET
	  |
	  )
	;

new_expr [AST parent] returns [AST new_exp]
{
	new_exp = null; 
	AST mem_exp = null;
}
	: mem_exp = member_expr [parent] { new_exp = mem_exp; }
	;
        
call_expr [AST parent] returns [Call func_call]
{
	func_call = null;
	AST member = null;
	AST args1 = null;
	AST args2 = null;
}
	: member = member_expr [parent] args1 = arguments [parent] args2 = call_aux [parent]
	  {
		  func_call = new Call (parent, member, args1, args2);
	  }
	;

call_aux [AST parent] returns [AST args]
{
	args = null;
} 
	: 
	( arguments [parent]
	| OPEN_BRACKET expr [parent] CLOSE_BRACKET
	| DOT IDENTIFIER
	) call_aux [parent]
	|
	;

arguments [AST parent] returns [Args args]
{
	Args tmp = new Args ();
	args = null; 
}
	: OPEN_PARENS (arguments_list [tmp, parent] { args = tmp; } | ) CLOSE_PARENS
	;

arguments_list [Args args, AST parent]
{
	AST a = null;
}
	: a = assignment_expr [parent] { args.Add (a); } 
	  (COMMA a = assignment_expr [parent] { args.Add (a); })*
	;

left_hand_side_expr [AST parent] returns [AST lhe]
{
	lhe = null;
	Call call = null;
}
	: (call_expr [parent])=> call = call_expr [parent] { lhe = call; }
	| lhe = new_expr [parent]
	;

postfix_expr [AST parent] returns [Unary post_expr]
{
	post_expr = null;
	JSToken op = JSToken.None;
	AST left = null;
}
	: left = left_hand_side_expr [parent] ( INCREMENT { op = JSToken.Increment; } 
					      | DECREMENT { op = JSToken.Decrement; } 
					      | )
	  {
		  post_expr = new Unary (parent, left, op);
	  }
	;

unary_expr [AST parent] returns [Unary unary_exprn]
{
	unary_exprn = null;
	JSToken op = JSToken.None;
	AST u_expr = null;
}
	: unary_exprn = postfix_expr [parent]
	| op = unary_op u_expr = unary_expr [parent]
	  { 
		  unary_exprn = new Unary (parent, u_expr, op); 
	  }
	;

unary_op returns [JSToken unary_op]
{ unary_op = JSToken.None; }
	: "delete" { unary_op = JSToken.Delete; }
	| "void" { unary_op = JSToken.Void; }
	| "typeof" { unary_op = JSToken.Typeof; }
	| INCREMENT { unary_op = JSToken.Increment; }
	| DECREMENT { unary_op = JSToken.Decrement; }
	| PLUS { unary_op = JSToken.Plus; }
	| MINUS { unary_op = JSToken.Minus; }
	| BITWISE_NOT { unary_op = JSToken.BitwiseNot; }
	| LOGICAL_NOT { unary_op = JSToken.LogicalNot; }
	;

multiplicative_expr [AST parent] returns [AST mult_expr]
{
	mult_expr = null;
	Unary left = null;
	AST right = null;
}
	: left = unary_expr [parent] right = multiplicative_aux [parent]
	  {
		  if (right == null)
			  mult_expr = left;
		  else
		  	  mult_expr = new Binary (parent, left, right, ((Binary) right).old_op);
	  }
	;

multiplicative_aux [AST parent] returns [AST mult_aux]
{
	mult_aux = null;
	JSToken mult_op = JSToken.None;
	Unary left = null;
	AST right = null;
}
	: (( MULT { mult_op = JSToken.Multiply; }
	   | DIVISION { mult_op = JSToken.Divide; }
	   | MODULE { mult_op = JSToken.Modulo; }
	   ) left = unary_expr [parent] right = multiplicative_aux [parent]
	     {
			  if (right == null)
				  mult_aux = new Binary (parent, left, null, JSToken.None);
			  else
				  mult_aux = new Binary (parent, left, right, ((Binary) right).old_op);
			  ((Binary) mult_aux).old_op = mult_op;
	     }
	  | )
	;

additive_expr [AST parent] returns [AST add_expr]
{
	add_expr = null;
	AST left, right;
	left = right = null;
}
	: left = multiplicative_expr [parent] right = additive_aux [parent]
	  {
			  if (right == null)
				  add_expr = left;
			  else
				  add_expr = new Binary (parent, left, right, ((Binary) right).old_op);
	  }
	;

additive_aux [AST parent] returns [AST add_aux]
{
	add_aux = null;
	JSToken op = JSToken.None;
	AST left, right;
	left = right = null;
}
	: (( PLUS { op = JSToken.Plus; }
	   | MINUS { op = JSToken.Minus; }
	   ) left = multiplicative_expr [parent] right = additive_aux [parent]
	     {
		     if (right == null)
			     add_aux = new Binary (parent, left, null, JSToken.None);
		     else
			     add_aux = new Binary (parent, left, right, ((Binary) right).old_op);
		     ((Binary) add_aux).old_op = op;
	     }
	| )
	;

shift_expr [AST parent] returns [AST shift_expr]
{
	shift_expr = null;
	AST left, right;
	left = right = null;
}
	: left = additive_expr [parent] right = shift_aux [parent]
	  {
		  if (right == null)
			  shift_expr = left;
		  else
			  shift_expr = new Binary (parent, left, right, ((Binary) right).old_op);
	  }
	;

shift_aux [AST parent] returns [AST shift_auxr]
{ 
	shift_auxr = null; 
	JSToken op = JSToken.None;
	AST left, right;
	left = right = null;
}
	: (op = shift_op left = additive_expr [parent] right = shift_aux [parent]
	   {
		   if (right == null)
			   shift_auxr = new Binary (parent, left, null, JSToken.None);
		   else
			   shift_auxr = new Binary (parent, left, right, ((Binary) right).old_op);

		   ((Binary) shift_auxr).old_op = op;
	   }
	  | )
	;

shift_op returns [JSToken shift_op]
{ shift_op = JSToken.None; }
	: SHIFT_LEFT { shift_op = JSToken.LeftShift; }
	| SHIFT_RIGHT { shift_op = JSToken.RightShift; }
	| UNSIGNED_SHIFT_RIGHT { shift_op = JSToken.UnsignedRightShift; }
	;

relational_expr [AST parent] returns [AST rel_expr]
{
	rel_expr = null;
	AST left = null;
	Relational right = null;
}
	: left = shift_expr [parent] right = relational_aux [parent]
	  {
		  if (right == null)
			  rel_expr = left;
		  else
			  rel_expr = new Relational (parent, left, right, right.old_op);
	  }
	;

relational_aux [AST parent] returns [Relational rel_aux]
{
	rel_aux = null;
	JSToken op = JSToken.None;
	AST left = null;
	Relational right = null;
}
	: (op = relational_op left = shift_expr [parent] right = relational_aux [parent]
	   {
		   if (right == null)
			  rel_aux = new Relational (parent, left, null, JSToken.None);
		   else
			   rel_aux = new Relational (parent, left, right, right.old_op);
		   rel_aux.old_op = op;

	   }
	 | )
	;

relational_op returns [JSToken rel_op]
{ rel_op = JSToken.None; }
	: LESS_THAN { rel_op = JSToken.LessThan; }
	| GREATER_THAN { rel_op = JSToken.GreaterThan; }
	| LESS_EQ { rel_op = JSToken.LessThanEqual; }
	| GREATER_EQ { rel_op = JSToken.GreaterThanEqual; }
	| "instanceof" { rel_op = JSToken.InstanceOf; }
	;


equality_expr [AST parent] returns [AST eq_expr]
{
	eq_expr = null;
	AST left = null;
	Equality right = null;
}
	: left = relational_expr [parent] right = equality_aux [parent]
	  {
		  if (right == null)
			  eq_expr = left;
		  else {
			  eq_expr = new Equality (parent, left, right, right.old_op);
		  }
	  }
	;

equality_aux [AST parent] returns [Equality eq_aux]
{
	eq_aux = null;
	AST left = null;
	Equality right = null;
	JSToken op = JSToken.None;
}
	: (op = equality_op left = relational_expr [parent] right = equality_aux [parent]
	   {
		   if (right == null)
			  eq_aux = new Equality (parent, left, null, JSToken.None);
		   else
			  eq_aux = new Equality (parent, left, right, right.old_op);

		  eq_aux.old_op = op;
	   }
	  | )
	;

equality_op returns [JSToken eq_op]
{ eq_op = JSToken.None; }
	: EQ { eq_op = JSToken.Equal; }
	| NEQ { eq_op = JSToken.NotEqual; }
	| STRICT_EQ { eq_op = JSToken.StrictEqual; }
	| STRICT_NEQ { eq_op = JSToken.StrictNotEqual; }
	;

bitwise_and_expr [AST parent] returns [AST bit_and_expr]
{
	bit_and_expr = null;
    AST left;
	AST right;
	left = null;
	right = null;
}
	: left = equality_expr [parent]  right = bitwise_and_aux [parent]
	  {
		  if (right == null)
			  bit_and_expr = left;
		  else
			  bit_and_expr = new Binary (parent, left, right, JSToken.BitwiseAnd);
	  }
	;

bitwise_and_aux [AST parent] returns [AST bit_and_aux]
{
	bit_and_aux = null;
	AST left = null;
	AST right = null;
}
	: (BITWISE_AND left = equality_expr [parent] right = bitwise_and_aux [parent]
	   {
		   if (right == null)
			   bit_and_aux = left;
		   else
			   bit_and_aux = new Binary (parent, left, right, JSToken.BitwiseAnd);
	   }
	  | )
		  
	;

bitwise_xor_expr [AST parent] returns [AST bit_xor_expr]
{
	bit_xor_expr = null;
	AST left, right;
	left = right = null;
}
	: left = bitwise_and_expr [parent] right = bitwise_xor_aux [parent]
	  {
		  if (right == null)
			  bit_xor_expr = left;
		  else
			  bit_xor_expr = new Binary (parent, left, right, JSToken.BitwiseXor);
	  }
	;

bitwise_xor_aux [AST parent] returns [AST bit_xor_aux]
{
	bit_xor_aux = null;
	AST left, right;
	left = right = null;
}
	: (BITWISE_XOR left = bitwise_and_expr [parent] right = bitwise_xor_aux [parent]
	   {
		  if (right == null)
			  bit_xor_aux = left;
		  else
			  bit_xor_aux = new Binary (parent, left, right, JSToken.BitwiseXor);
	   }
	  | )
	;

bitwise_or_expr [AST parent] returns [AST bit_or_expr]
{ 
	bit_or_expr = null;
	AST left, right;
	left = right = null;
}
	: left = bitwise_xor_expr [parent] right = bitwise_or_aux [parent]
	  {
	  	  if (right == null)
			  bit_or_expr = left;
		  else
			  bit_or_expr = new Binary (parent, left, right, JSToken.BitwiseOr);
	  }
	;

bitwise_or_aux [AST parent] returns [AST bit_or_aux]
{ 
	bit_or_aux = null;
	AST left, right;
	left = right = null;
}
	: (BITWISE_OR left = bitwise_xor_expr [parent] right = bitwise_or_aux [parent]
	   {
		   if (right == null)
			   bit_or_aux = left;
 		   else
			   bit_or_aux = new Binary (parent, left, right, JSToken.BitwiseOr);
	   }
	  | )
	;

logical_and_expr [AST parent] returns [AST log_and_expr]
{
	log_and_expr = null;
	AST left, right;
	left = right = null;
}
	: left = bitwise_or_expr [parent] right = logical_and_aux [parent]
	  {
		  if (right == null)
			  log_and_expr = left;
	  	  else
			  log_and_expr = new Binary (parent, left, right, JSToken.LogicalAnd);
	  }
	;

logical_and_aux [AST parent] returns [AST log_and_aux]
{
	log_and_aux = null;
	AST left, right;
	left = right = null;
}
	: (LOGICAL_AND left = bitwise_or_expr [parent] right = logical_and_aux [parent]
	   {
	   	   if (right == null)
			   log_and_aux = left;
		   else
			   log_and_aux = new Binary (parent, left, right, JSToken.LogicalAnd);
	   }
	  | )
	;

logical_or_expr [AST parent] returns [AST log_or_expr]
{ 
	log_or_expr = null; 
	AST left, right;
	left = right = null;
}
	:  left = logical_and_expr [parent] right = logical_or_aux [parent]
	   {
		  if (right == null)
		  	  log_or_expr = left;
		  else
			  log_or_expr = new Binary (parent, left, right, JSToken.LogicalOr);
	   }
					    			
	;

logical_or_aux [AST parent] returns [AST log_or_aux]
{ 
	AST left, right;
	log_or_aux = null;
	left = right = null;	
}
	: (LOGICAL_OR left = logical_and_expr [parent] right = logical_or_aux [parent]
	   {
		  if (right == null)
		  	  log_or_aux = left; 
		  else
			  log_or_aux = new Binary (parent, left, right, JSToken.LogicalOr);
	   }
	  | )
	;

cond_expr [AST parent] returns [AST conditional]
{
	conditional = null; 
	AST cond;
	AST trueExpr, falseExpr;
	cond = null;
	trueExpr = falseExpr = null;
}
	: cond = logical_or_expr [parent]
	  (INTERR trueExpr = assignment_expr [parent]
	   COLON falseExpr = assignment_expr [parent]
	   { 
	  	  if (trueExpr != null && falseExpr != null) {
		  	  Conditional c = new Conditional (parent, (AST) cond, trueExpr, falseExpr); 
			  conditional =  c;
		  }
	   }
	  | { conditional = cond; } )

	;

assignment_op returns [JSToken assign_op]
{
    assign_op = JSToken.None;
}
	: ASSIGN { assign_op = JSToken.Assign; }
	| MULT_ASSIGN { assign_op = JSToken.MultiplyAssign; }
	| DIV_ASSIGN { assign_op = JSToken.DivideAssign; }
	| MOD_ASSIGN { assign_op = JSToken.ModuloAssign; }
	| ADD_ASSIGN { assign_op = JSToken.PlusAssign; }
	| SUB_ASSIGN { assign_op = JSToken.MinusAssign; }
	| SHIFT_LEFT_ASSIGN { assign_op = JSToken.LeftShiftAssign; }
	| SHIFT_RIGHT_ASSIGN { assign_op = JSToken.RightShiftAssign; }
	| AND_ASSIGN { assign_op = JSToken.BitwiseAndAssign; }
	| XOR_ASSIGN { assign_op = JSToken.BitwiseXorAssign; }
	| OR_ASSIGN { assign_op = JSToken.BitwiseOrAssign; }
	;
	

primary_expr [AST parent] returns [AST prim_exp]
{
	prim_exp = null;
	AST l = null;
	Expression e = null;
}
	: p:"this" { prim_exp = new This (); }
	| object_literal
	| id:IDENTIFIER 
	  { 
		Identifier ident = new Identifier (id.getText ());
		prim_exp = (AST) ident;
	  }
	| l = literal [parent] { prim_exp = l; }
	| array_literal
	| OPEN_PARENS e = expr [parent] { prim_exp = e; } CLOSE_PARENS
	; 

object_literal
	: OPEN_BRACE 
	   ((property_name COLON)=> property_name COLON assignment_expr [null] 
	    (COMMA property_name COLON assignment_expr [null])*
	   | (statement [null])*
	   ) 
	  CLOSE_BRACE
	;

literal [AST parent] returns [AST l]
{
	l = null; 
}
	: "null"
	| "true"
	  {
		  BooleanLiteral bl = new BooleanLiteral (parent, true);
		  l = bl;
	  }
	| "false"
	  {
		  BooleanLiteral bl = new BooleanLiteral (parent, false);
		  l = bl;
	  }
	| s:STRING_LITERAL
	  {
		  StringLiteral str = new StringLiteral (s.getText ());
		  l = str;
	  }      
	| l = numeric_literal
	;

property_name_and_value_list
	: (property_name COLON primary_expr [null])+
	;

property_name
	: (IDENTIFIER | STRING_LITERAL | numeric_literal) 
	;

array_literal
	: OPEN_BRACKET (primary_expr [null] (COMMA primary_expr [null])* | ) CLOSE_BRACKET
	;	

numeric_literal returns [NumericLiteral num_lit]
{
	num_lit = null;
}
	: d:DECIMAL_LITERAL { num_lit = new NumericLiteral (Convert.ToSingle (d.getText ())); }
	| HEX_INTEGER_LITERAL
	;


line_terminator
	: LINE_FEED
	| CARRIAGE_RETURN
	| LINE_SEPARATOR
	| PARAGRAPH_SEPARATOR
	;

white_space
	: TAB
	| VERTICAL_TAB
	| FORM_FEED
	| SPACE
	| NO_BREAK_SPACE
	;

//
// Lexer
//

class JScriptLexer extends Lexer;

options {
	charVocabulary = '\u0000'..'\uFFFE';
	testLiterals = false;
	k = 3;
}

DECIMAL_LITERAL: ('0'  | ('1'..'9')('0'..'9')*) (DOT ('0'..'9')* | ) (('e' | 'E') (('+' | '-' | ) ('0'..'9')+) | )
    ;

HEX_INTEGER_LITERAL: '0' ('x' | 'X') ('0'..'9' | 'a'..'f' | 'A'..'F')+
    ;

STRING_LITERAL
	: '"' (~('"' | '\\' | '\u000A' | '\u000D' | '\u2028' | '\u2029'))* '"'
	;

IDENTIFIER
options { testLiterals = true; }
	: ('a'..'z' | 'A'..'Z') ('a'..'z' | 'A'..'Z' | '0'..'9')*
	;

//
// Operators
//
DOT: '.';
COMMA: ',';

INCREMENT: "++";
DECREMENT: "--";
PLUS: '+';
MINUS: '-';
BITWISE_NOT: '~';
LOGICAL_NOT: '!';

MULT: '*';
DIVISION: '/';
MODULE: '%';
ASSIGN: '=';


SHIFT_LEFT: "<<";
SHIFT_RIGHT: ">>";
UNSIGNED_SHIFT_RIGHT: ">>>";
	
LESS_THAN: '<';
GREATER_THAN: '>';
LESS_EQ: "<=";
GREATER_EQ: ">=";

EQ: "==";
NEQ: "!=";
STRICT_EQ: "===";
STRICT_NEQ: "!==";

MULT_ASSIGN: "*=";
DIV_ASSIGN: "/=";
MOD_ASSIGN: "%=";
ADD_ASSIGN: "+=";
SUB_ASSIGN: "-=";
SHIFT_LEFT_ASSIGN: "<<=";
SHIFT_RIGHT_ASSIGN: ">>=";
AND_ASSIGN: "&=";
XOR_ASSIGN: "^=";
OR_ASSIGN: "|=";
INTERR: '?';
LOGICAL_OR: "||";
LOGICAL_AND: "&&";
BITWISE_OR: '|';
BITWISE_AND: '&';
BITWISE_XOR: '^';


OPEN_PARENS: '(';
CLOSE_PARENS: ')';
OPEN_BRACKET: '[';
CLOSE_BRACKET: ']';
OPEN_BRACE: '{';
CLOSE_BRACE: '}';

//
// Punctuators
//
SEMI_COLON: ';';
COLON: ':';


//
// Comments
//

SL_COMMENT
	: "//" (~('\u000A' | '\u000D' | '\u2028' | '\u2029'))*
	  { $setType (Token.SKIP); }
	;
//
// Line terminator tokens
//
LINE_FEED
	: '\u000A' { $setType (Token.SKIP); newline (); }
	;

CARRIAGE_RETURN
	: '\u000D' { $setType (Token.SKIP); newline ();}
	;

LINE_SEPARATOR
	: '\u2028' { $setType (Token.SKIP); newline ();}
	;

PARAGRAPH_SEPARATOR
	: '\u2029' { $setType (Token.SKIP); newline ();}
	;

//
// White space tokens
//
TAB
	: '\u0009' { $setType (Token.SKIP); }
	;

VERTICAL_TAB
	: '\u000B' { $setType (Token.SKIP); }
	;

FORM_FEED
	: '\u000C' { $setType (Token.SKIP); }
	;

SPACE
	: '\u0020' { $setType (Token.SKIP); }
	;

NO_BREAK_SPACE
	: '\u00A0' { $setType (Token.SKIP); }
	;
