//
// delegate.cs: Delegate Handler
//
// Authors:
//     Ravi Pratap (ravi@ximian.com)
//     Miguel de Icaza (miguel@ximian.com)
//     Marek Safar (marek.safar@gmail.com)
//
// Dual licensed under the terms of the MIT X11 or GNU GPL
//
// Copyright 2001 Ximian, Inc (http://www.ximian.com)
// Copyright 2003-2009 Novell, Inc (http://www.novell.com)
//

using System;
using System.Reflection;
using System.Reflection.Emit;

namespace Mono.CSharp {

	//
	// Delegate container implementation
	//
	public class Delegate : TypeContainer
	{
 		FullNamedExpression ReturnType;
		public readonly AParametersCollection Parameters;

		// TODO: Maybe I can keep member cache only and not the builders
		Constructor Constructor;
		Method InvokeBuilder;
		Method BeginInvokeBuilder;
		Method EndInvokeBuilder;

		static readonly string[] attribute_targets = new string [] { "type", "return" };

		public static readonly string InvokeMethodName = "Invoke";
		
		Expression instance_expr;
		ReturnParameter return_attributes;

		const Modifiers MethodModifiers = Modifiers.PUBLIC | Modifiers.VIRTUAL;

		const Modifiers AllowedModifiers =
			Modifiers.NEW |
			Modifiers.PUBLIC |
			Modifiers.PROTECTED |
			Modifiers.INTERNAL |
			Modifiers.UNSAFE |
			Modifiers.PRIVATE;

 		public Delegate (NamespaceEntry ns, DeclSpace parent, FullNamedExpression type,
				 Modifiers mod_flags, MemberName name, ParametersCompiled param_list,
				 Attributes attrs)
			: base (ns, parent, name, attrs, MemberKind.Delegate)

		{
			this.ReturnType = type;
			ModFlags        = ModifiersExtensions.Check (AllowedModifiers, mod_flags,
							   IsTopLevel ? Modifiers.INTERNAL :
							   Modifiers.PRIVATE, name.Location, Report);
			Parameters      = param_list;
		}

		public override void ApplyAttributeBuilder (Attribute a, CustomAttributeBuilder cb, PredefinedAttributes pa)
		{
			if (a.Target == AttributeTargets.ReturnValue) {
				if (return_attributes == null)
					return_attributes = new ReturnParameter (this, InvokeBuilder.MethodBuilder, Location);

				return_attributes.ApplyAttributeBuilder (a, cb, pa);
				return;
			}

			base.ApplyAttributeBuilder (a, cb, pa);
		}

		public override AttributeTargets AttributeTargets {
			get {
				return AttributeTargets.Delegate;
			}
		}

		protected override Type BaseType {
			get {
				return TypeManager.multicast_delegate_type;
			}
		}

		protected override bool DoDefineMembers ()
		{
			if (IsGeneric) {
				foreach (TypeParameter type_param in TypeParameters) {
					if (!type_param.Resolve (this))
						return false;
				}

				foreach (TypeParameter type_param in TypeParameters) {
					if (!type_param.DefineType (this))
						return false;
				}
			}

			member_cache = new MemberCache (BaseType, this);

			var ctor_parameters = ParametersCompiled.CreateFullyResolved (
				new [] {
					new Parameter (new TypeExpression (TypeManager.object_type, Location), "object", Parameter.Modifier.NONE, null, Location),
					new Parameter (new TypeExpression (TypeManager.intptr_type, Location), "method", Parameter.Modifier.NONE, null, Location)
				},
				new [] {
					TypeManager.object_type,
					TypeManager.intptr_type
				}
			);

			Constructor = new Constructor (this, System.Reflection.ConstructorInfo.ConstructorName,
				Modifiers.PUBLIC, null, ctor_parameters, null, Location);
			Constructor.Define ();

			//
			// Here the various methods like Invoke, BeginInvoke etc are defined
			//
			// First, call the `out of band' special method for
			// defining recursively any types we need:
			//
			var p = Parameters.AsCompiled;

			if (!p.Resolve (this))
				return false;

			//
			// Invoke method
			//

			// Check accessibility
			foreach (var partype in p.Types) {
				if (!IsAccessibleAs (partype)) {
					Report.SymbolRelatedToPreviousError (partype);
					Report.Error (59, Location,
						"Inconsistent accessibility: parameter type `{0}' is less accessible than delegate `{1}'",
						TypeManager.CSharpName (partype), GetSignatureForError ());
				}
			}

			ReturnType = ReturnType.ResolveAsTypeTerminal (this, false);
			if (ReturnType == null)
				return false;

			var ret_type = ReturnType.Type;

			//
			// We don't have to check any others because they are all
			// guaranteed to be accessible - they are standard types.
			//
			if (!IsAccessibleAs (ret_type)) {
				Report.SymbolRelatedToPreviousError (ret_type);
				Report.Error (58, Location,
						  "Inconsistent accessibility: return type `" +
						  TypeManager.CSharpName (ret_type) + "' is less " +
						  "accessible than delegate `" + GetSignatureForError () + "'");
				return false;
			}

			CheckProtectedModifier ();

			if (RootContext.StdLib && TypeManager.IsSpecialType (ret_type)) {
				Method.Error1599 (Location, ret_type, Report);
				return false;
			}

			TypeManager.CheckTypeVariance (ret_type, Variance.Covariant, this);

			InvokeBuilder = new Method (this, null, ReturnType, MethodModifiers, new MemberName (InvokeMethodName), p, null);
			InvokeBuilder.Define ();

			//
			// Don't emit async method for compiler generated delegates (e.g. dynamic site containers)
			//
			if (TypeManager.iasyncresult_type != null && TypeManager.asynccallback_type != null && !IsCompilerGenerated) {
				DefineAsyncMethods (Parameters.CallingConvention);
			}

			return true;
		}

		void DefineAsyncMethods (CallingConventions cc)
		{
			//
			// BeginInvoke
			//
			Parameter[] compiled = new Parameter[Parameters.Count];
			for (int i = 0; i < compiled.Length; ++i)
				compiled[i] = new Parameter (new TypeExpression (Parameters.Types[i], Location),
					Parameters.FixedParameters[i].Name,
					Parameters.FixedParameters[i].ModFlags & (Parameter.Modifier.REF | Parameter.Modifier.OUT),
					null, Location);

			ParametersCompiled async_parameters = new ParametersCompiled (Compiler, compiled);

			async_parameters = ParametersCompiled.MergeGenerated (Compiler, async_parameters, false,
				new Parameter[] {
					new Parameter (new TypeExpression (TypeManager.asynccallback_type, Location), "callback", Parameter.Modifier.NONE, null, Location),
					new Parameter (new TypeExpression (TypeManager.object_type, Location), "object", Parameter.Modifier.NONE, null, Location)
				},
				new [] {
					TypeManager.asynccallback_type,
					TypeManager.object_type
				}
			);

			BeginInvokeBuilder = new Method (this, null,
				new TypeExpression (TypeManager.iasyncresult_type, Location), MethodModifiers,
				new MemberName ("BeginInvoke"), async_parameters, null);
			BeginInvokeBuilder.Define ();

			//
			// EndInvoke is a bit more interesting, all the parameters labeled as
			// out or ref have to be duplicated here.
			//

			//
			// Define parameters, and count out/ref parameters
			//
			ParametersCompiled end_parameters;
			int out_params = 0;

			foreach (Parameter p in Parameters.FixedParameters) {
				if ((p.ModFlags & Parameter.Modifier.ISBYREF) != 0)
					++out_params;
			}

			if (out_params > 0) {
				var end_param_types = new Type [out_params];
				Parameter[] end_params = new Parameter[out_params];

				int param = 0;
				for (int i = 0; i < Parameters.FixedParameters.Length; ++i) {
					Parameter p = Parameters.AsCompiled [i];
					if ((p.ModFlags & Parameter.Modifier.ISBYREF) == 0)
						continue;

					end_param_types[param] = Parameters.Types[i];
					end_params[param] = p;
					++param;
				}
				end_parameters = ParametersCompiled.CreateFullyResolved (end_params, end_param_types);
			} else {
				end_parameters = ParametersCompiled.EmptyReadOnlyParameters;
			}

			end_parameters = ParametersCompiled.MergeGenerated (Compiler, end_parameters, false,
				new Parameter (
					new TypeExpression (TypeManager.iasyncresult_type, Location),
					"result", Parameter.Modifier.NONE, null, Location),
				TypeManager.iasyncresult_type);

			//
			// Create method, define parameters, register parameters with type system
			//
			EndInvokeBuilder = new Method (this, null, ReturnType, MethodModifiers, new MemberName ("EndInvoke"), end_parameters, null);
			EndInvokeBuilder.Define ();
		}

		public override void Emit ()
		{
			if (TypeManager.IsDynamicType (ReturnType.Type)) {
				return_attributes = new ReturnParameter (this, InvokeBuilder.MethodBuilder, Location);
				PredefinedAttributes.Get.Dynamic.EmitAttribute (return_attributes.Builder);
			} else {
				var trans_flags = TypeManager.HasDynamicTypeUsed (ReturnType.Type);
				if (trans_flags != null) {
					var pa = PredefinedAttributes.Get.DynamicTransform;
					if (pa.Constructor != null || pa.ResolveConstructor (Location, TypeManager.bool_type.MakeArrayType ())) {
						return_attributes = new ReturnParameter (this, InvokeBuilder.MethodBuilder, Location);
						return_attributes.Builder.SetCustomAttribute (
							new CustomAttributeBuilder (pa.Constructor, new object [] { trans_flags }));
					}
				}
			}

			Parameters.AsCompiled.ApplyAttributes (InvokeBuilder.MethodBuilder);
			
			Constructor.ConstructorBuilder.SetImplementationFlags (MethodImplAttributes.Runtime);
			InvokeBuilder.MethodBuilder.SetImplementationFlags (MethodImplAttributes.Runtime);

			if (BeginInvokeBuilder != null) {
				BeginInvokeBuilder.Parameters.ApplyAttributes (BeginInvokeBuilder.MethodBuilder);

				BeginInvokeBuilder.MethodBuilder.SetImplementationFlags (MethodImplAttributes.Runtime);
				EndInvokeBuilder.MethodBuilder.SetImplementationFlags (MethodImplAttributes.Runtime);
			}

			if (OptAttributes != null) {
				OptAttributes.Emit ();
			}

			base.Emit ();
		}

		protected override TypeAttributes TypeAttr {
			get {
				return ModifiersExtensions.TypeAttr (ModFlags, IsTopLevel) |
					TypeAttributes.Class | TypeAttributes.Sealed |
					base.TypeAttr;
			}
		}

		public override string[] ValidAttributeTargets {
			get {
				return attribute_targets;
			}
		}

		//TODO: duplicate
		protected override bool VerifyClsCompliance ()
		{
			if (!base.VerifyClsCompliance ()) {
				return false;
			}

			Parameters.AsCompiled.VerifyClsCompliance (this);

			if (!AttributeTester.IsClsCompliant (ReturnType.Type)) {
				Report.Warning (3002, 1, Location, "Return type of `{0}' is not CLS-compliant",
					GetSignatureForError ());
			}
			return true;
		}


		public static MethodSpec GetConstructor (CompilerContext ctx, Type container_type, Type delegate_type)
		{
			Type dt = delegate_type;
			Type[] g_args = null;
			if (TypeManager.IsGenericType (delegate_type)) {
				g_args = TypeManager.GetTypeArguments (delegate_type);
				delegate_type = TypeManager.DropGenericTypeArguments (delegate_type);
			}

			Delegate d = TypeManager.LookupDelegate (delegate_type);
			if (d != null) {
				if (g_args != null)
					return Import.CreateMethod (TypeBuilder.GetConstructor (dt, d.Constructor.ConstructorBuilder));

				return d.Constructor.Spec;
			}

			Expression ml = Expression.MemberLookup (ctx, container_type,
				null, dt, ConstructorInfo.ConstructorName, MemberTypes.Constructor,
				BindingFlags.Public | BindingFlags.Instance | BindingFlags.DeclaredOnly, Location.Null);

			MethodGroupExpr mg = ml as MethodGroupExpr;
			if (mg == null) {
				ctx.Report.Error (-100, Location.Null, "Internal error: could not find delegate constructor!");
				// FIXME: null will cause a crash later
				return null;
			}

			return mg.Methods[0];
		}

		//
		// Returns the MethodBase for "Invoke" from a delegate type, this is used
		// to extract the signature of a delegate.
		//
		public static MethodSpec GetInvokeMethod (CompilerContext ctx, Type container_type, Type delegate_type)
		{
			Type dt = delegate_type;

			Type[] g_args = null;
			if (TypeManager.IsGenericType (delegate_type)) {
				g_args = TypeManager.GetTypeArguments (delegate_type);
				delegate_type = TypeManager.DropGenericTypeArguments (delegate_type);
			}

			Delegate d = TypeManager.LookupDelegate (delegate_type);
			MethodSpec invoke;
			if (d != null) {
				if (g_args != null) {
					invoke = Import.CreateMethod (TypeBuilder.GetMethod (dt, d.InvokeBuilder.MethodBuilder));
#if MS_COMPATIBLE
//					ParametersCompiled p = (ParametersCompiled) d.Parameters.InflateTypes (g_args, g_args);
//					TypeManager.RegisterMethod (invoke, p);
#endif
					return invoke;
				}
				return d.InvokeBuilder.Spec;
			}

			Expression ml = Expression.MemberLookup (ctx, container_type, null, dt,
				"Invoke", Location.Null);

			MethodGroupExpr mg = ml as MethodGroupExpr;
			if (mg == null) {
				ctx.Report.Error (-100, Location.Null, "Internal error: could not find Invoke method!");
				// FIXME: null will cause a crash later
				return null;
			}

			invoke = mg.Methods[0];
#if MS_COMPATIBLE
//			if (g_args != null) {
//				AParametersCollection p = TypeManager.GetParameterData (invoke);
//				p = p.InflateTypes (g_args, g_args);
//				TypeManager.RegisterMethod (invoke, p);
//				return invoke;
//			}
#endif

			return invoke;
		}

		//
		// 15.2 Delegate compatibility
		//
		public static bool IsTypeCovariant (Expression a, Type b)
		{
			//
			// For each value parameter (a parameter with no ref or out modifier), an 
			// identity conversion or implicit reference conversion exists from the
			// parameter type in D to the corresponding parameter type in M
			//
			if (a.Type == b)
				return true;

			if (RootContext.Version == LanguageVersion.ISO_1)
				return false;

			return Convert.ImplicitReferenceConversionExists (a, b);
		}

		public static string FullDelegateDesc (MethodSpec invoke_method)
		{
			return TypeManager.GetFullNameSignature (invoke_method.MetaInfo).Replace (".Invoke", "");
		}
		
		public Expression InstanceExpression {
			get {
				return instance_expr;
			}
			set {
				instance_expr = value;
			}
		}
	}

	//
	// Base class for `NewDelegate' and `ImplicitDelegateCreation'
	//
	public abstract class DelegateCreation : Expression, MethodGroupExpr.IErrorHandler
	{
		protected MethodSpec constructor_method;
		protected MethodSpec delegate_method;
		// We keep this to handle IsBase only
		protected MethodGroupExpr method_group;
		protected Expression delegate_instance_expression;

		// TODO: Should either cache it or use interface to abstract it
		public static Arguments CreateDelegateMethodArguments (AParametersCollection pd, Location loc)
		{
			Arguments delegate_arguments = new Arguments (pd.Count);
			for (int i = 0; i < pd.Count; ++i) {
				Argument.AType atype_modifier;
				Type atype = pd.Types [i];
				switch (pd.FixedParameters [i].ModFlags) {
				case Parameter.Modifier.REF:
					atype_modifier = Argument.AType.Ref;
					//atype = atype.GetElementType ();
					break;
				case Parameter.Modifier.OUT:
					atype_modifier = Argument.AType.Out;
					//atype = atype.GetElementType ();
					break;
				default:
					atype_modifier = 0;
					break;
				}
				delegate_arguments.Add (new Argument (new TypeExpression (atype, loc), atype_modifier));
			}
			return delegate_arguments;
		}

		public override Expression CreateExpressionTree (ResolveContext ec)
		{
			MemberAccess ma = new MemberAccess (new MemberAccess (new QualifiedAliasMember ("global", "System", loc), "Delegate", loc), "CreateDelegate", loc);

			Arguments args = new Arguments (3);
			args.Add (new Argument (new TypeOf (new TypeExpression (type, loc), loc)));
			args.Add (new Argument (new NullLiteral (loc)));
			args.Add (new Argument (new TypeOfMethod (delegate_method, loc)));
			Expression e = new Invocation (ma, args).Resolve (ec);
			if (e == null)
				return null;

			e = Convert.ExplicitConversion (ec, e, type, loc);
			if (e == null)
				return null;

			return e.CreateExpressionTree (ec);
		}

		protected override Expression DoResolve (ResolveContext ec)
		{
			constructor_method = Delegate.GetConstructor (ec.Compiler, ec.CurrentType, type);

			var invoke_method = Delegate.GetInvokeMethod (ec.Compiler, ec.CurrentType, type);
			method_group.DelegateType = type;
			method_group.CustomErrorHandler = this;

			Arguments arguments = CreateDelegateMethodArguments (invoke_method.Parameters, loc);
			method_group = method_group.OverloadResolve (ec, ref arguments, false, loc);
			if (method_group == null)
				return null;

			delegate_method = (MethodSpec) method_group;
			
			if (TypeManager.IsNullableType (delegate_method.DeclaringType)) {
				ec.Report.Error (1728, loc, "Cannot create delegate from method `{0}' because it is a member of System.Nullable<T> type",
					TypeManager.GetFullNameSignature (delegate_method.MetaInfo));
				return null;
			}		
			
			Invocation.IsSpecialMethodInvocation (ec, delegate_method, loc);

			ExtensionMethodGroupExpr emg = method_group as ExtensionMethodGroupExpr;
			if (emg != null) {
				delegate_instance_expression = emg.ExtensionExpression;
				Type e_type = delegate_instance_expression.Type;
				if (TypeManager.IsValueType (e_type)) {
					ec.Report.Error (1113, loc, "Extension method `{0}' of value type `{1}' cannot be used to create delegates",
						TypeManager.CSharpSignature (delegate_method.MetaInfo), TypeManager.CSharpName (e_type));
				}
			}

			Type rt = TypeManager.TypeToCoreType (delegate_method.ReturnType);
			Expression ret_expr = new TypeExpression (rt, loc);
			if (!Delegate.IsTypeCovariant (ret_expr, (TypeManager.TypeToCoreType (invoke_method.ReturnType)))) {
				Error_ConversionFailed (ec, delegate_method, ret_expr);
			}

			if (Invocation.IsMethodExcluded (delegate_method, loc)) {
				ec.Report.SymbolRelatedToPreviousError (delegate_method.MetaInfo);
				MethodOrOperator m = TypeManager.GetMethod (delegate_method.MetaInfo) as MethodOrOperator;
				if (m != null && m.IsPartialDefinition) {
					ec.Report.Error (762, loc, "Cannot create delegate from partial method declaration `{0}'",
						TypeManager.CSharpSignature (delegate_method.MetaInfo));
				} else {
					ec.Report.Error (1618, loc, "Cannot create delegate with `{0}' because it has a Conditional attribute",
						TypeManager.CSharpSignature (delegate_method.MetaInfo));
				}
			}

			DoResolveInstanceExpression (ec);
			eclass = ExprClass.Value;
			return this;
		}

		void DoResolveInstanceExpression (ResolveContext ec)
		{
			//
			// Argument is another delegate
			//
			if (delegate_instance_expression != null)
				return;

			if (method_group.IsStatic) {
				delegate_instance_expression = null;
				return;
			}

			Expression instance = method_group.InstanceExpression;
			if (instance != null && instance != EmptyExpression.Null) {
				delegate_instance_expression = instance;
				Type instance_type = delegate_instance_expression.Type;
				if (TypeManager.IsValueType (instance_type) || TypeManager.IsGenericParameter (instance_type)) {
					delegate_instance_expression = new BoxedCast (
						delegate_instance_expression, TypeManager.object_type);
				}
			} else {
				delegate_instance_expression = ec.GetThis (loc);
			}
		}
		
		public override void Emit (EmitContext ec)
		{
			if (delegate_instance_expression == null)
				ec.ig.Emit (OpCodes.Ldnull);
			else
				delegate_instance_expression.Emit (ec);

			if (!delegate_method.DeclaringType.IsSealed && delegate_method.IsVirtual && !method_group.IsBase) {
				ec.ig.Emit (OpCodes.Dup);
				ec.ig.Emit (OpCodes.Ldvirtftn, (MethodInfo) delegate_method.MetaInfo);
			} else {
				ec.ig.Emit (OpCodes.Ldftn, (MethodInfo) delegate_method.MetaInfo);
			}

			ec.ig.Emit (OpCodes.Newobj, (ConstructorInfo) constructor_method.MetaInfo);
		}

		void Error_ConversionFailed (ResolveContext ec, MethodSpec method, Expression return_type)
		{
			var invoke_method = Delegate.GetInvokeMethod (ec.Compiler, ec.CurrentType, type);
			string member_name = delegate_instance_expression != null ?
				Delegate.FullDelegateDesc (method) :
				TypeManager.GetFullNameSignature (method.MetaInfo);

			ec.Report.SymbolRelatedToPreviousError (type);
			ec.Report.SymbolRelatedToPreviousError (method.MetaInfo);
			if (RootContext.Version == LanguageVersion.ISO_1) {
				ec.Report.Error (410, loc, "A method or delegate `{0} {1}' parameters and return type must be same as delegate `{2} {3}' parameters and return type",
					TypeManager.CSharpName (method.ReturnType), member_name,
					TypeManager.CSharpName (invoke_method.ReturnType), Delegate.FullDelegateDesc (invoke_method));
				return;
			}
			if (return_type == null) {
				ec.Report.Error (123, loc, "A method or delegate `{0}' parameters do not match delegate `{1}' parameters",
					member_name, Delegate.FullDelegateDesc (invoke_method));
				return;
			}

			ec.Report.Error (407, loc, "A method or delegate `{0} {1}' return type does not match delegate `{2} {3}' return type",
				return_type.GetSignatureForError (), member_name,
				TypeManager.CSharpName (invoke_method.ReturnType), Delegate.FullDelegateDesc (invoke_method));
		}

		public static bool ImplicitStandardConversionExists (ResolveContext ec, MethodGroupExpr mg, Type target_type)
		{
			if (target_type == TypeManager.delegate_type || target_type == TypeManager.multicast_delegate_type)
				return false;

			mg.DelegateType = target_type;
			var invoke = Delegate.GetInvokeMethod (ec.Compiler, null, target_type);

			Arguments arguments = CreateDelegateMethodArguments (invoke.Parameters, mg.Location);
			return mg.OverloadResolve (ec, ref arguments, true, mg.Location) != null;
		}

		public override void MutateHoistedGenericType (AnonymousMethodStorey storey)
		{
			if (delegate_instance_expression != null)
				delegate_instance_expression.MutateHoistedGenericType (storey);

			storey.MutateGenericMethod (delegate_method);
			storey.MutateConstructor (constructor_method);
		}

		#region IErrorHandler Members

		public bool NoExactMatch (ResolveContext ec, MethodSpec method)
		{
			if (method.IsGenericMethod)
				return false;

			Error_ConversionFailed (ec, method, null);
			return true;
		}

		public bool AmbiguousCall (ResolveContext ec, MethodSpec ambiguous)
		{
			return false;
		}

		#endregion
	}

	//
	// Created from the conversion code
	//
	public class ImplicitDelegateCreation : DelegateCreation
	{
		ImplicitDelegateCreation (Type t, MethodGroupExpr mg, Location l)
		{
			type = t;
			this.method_group = mg;
			loc = l;
		}

		static public Expression Create (ResolveContext ec, MethodGroupExpr mge,
						 Type target_type, Location loc)
		{
			ImplicitDelegateCreation d = new ImplicitDelegateCreation (target_type, mge, loc);
			return d.DoResolve (ec);
		}
	}
	
	//
	// A delegate-creation-expression, invoked from the `New' class 
	//
	public class NewDelegate : DelegateCreation
	{
		public Arguments Arguments;

		//
		// This constructor is invoked from the `New' expression
		//
		public NewDelegate (Type type, Arguments Arguments, Location loc)
		{
			this.type = type;
			this.Arguments = Arguments;
			this.loc  = loc; 
		}

		protected override Expression DoResolve (ResolveContext ec)
		{
			if (Arguments == null || Arguments.Count != 1) {
				ec.Report.Error (149, loc, "Method name expected");
				return null;
			}

			Argument a = Arguments [0];
			if (!a.ResolveMethodGroup (ec))
				return null;

			Expression e = a.Expr;

			AnonymousMethodExpression ame = e as AnonymousMethodExpression;
			if (ame != null && RootContext.Version != LanguageVersion.ISO_1) {
				e = ame.Compatible (ec, type);
				if (e == null)
					return null;

				return e.Resolve (ec);
			}

			method_group = e as MethodGroupExpr;
			if (method_group == null) {
				if (TypeManager.IsDynamicType (e.Type)) {
					e = Convert.ImplicitConversionRequired (ec, e, type, loc);
				} else if (!TypeManager.IsDelegateType (e.Type)) {
					e.Error_UnexpectedKind (ec, ResolveFlags.MethodGroup | ResolveFlags.Type, loc);
					return null;
				}

				//
				// An argument is not a method but another delegate
				//
				delegate_instance_expression = e;
				method_group = new MethodGroupExpr (new [] { 
					Delegate.GetInvokeMethod (ec.Compiler, ec.CurrentType, e.Type) }, e.Type, loc);
			}

			return base.DoResolve (ec);
		}
	}

	//
	// Invocation converted to delegate Invoke call
	//
	class DelegateInvocation : ExpressionStatement
	{
		readonly Expression InstanceExpr;
		Arguments arguments;
		MethodSpec method;
		
		public DelegateInvocation (Expression instance_expr, Arguments args, Location loc)
		{
			this.InstanceExpr = instance_expr;
			this.arguments = args;
			this.loc = loc;
		}
		
		public override Expression CreateExpressionTree (ResolveContext ec)
		{
			Arguments args = Arguments.CreateForExpressionTree (ec, this.arguments,
				InstanceExpr.CreateExpressionTree (ec));

			return CreateExpressionFactoryCall (ec, "Invoke", args);
		}

		protected override Expression DoResolve (ResolveContext ec)
		{
			if (InstanceExpr is EventExpr) {
				((EventExpr) InstanceExpr).Error_CannotAssign (ec);
				return null;
			}
			
			Type del_type = InstanceExpr.Type;
			if (del_type == null)
				return null;
			
			method = Delegate.GetInvokeMethod (ec.Compiler, ec.CurrentType, del_type);
			var mb = method;
			var me = new MethodGroupExpr (new [] { mb }, del_type, loc);
			me.InstanceExpression = InstanceExpr;

			AParametersCollection pd = mb.Parameters;
			int pd_count = pd.Count;

			int arg_count = arguments == null ? 0 : arguments.Count;

			bool params_method = pd.HasParams;
			bool is_params_applicable = false;
			bool is_applicable = me.IsApplicable (ec, ref arguments, arg_count, ref mb, ref is_params_applicable) == 0;
			if (arguments != null)
				arg_count = arguments.Count;

			if (!is_applicable && !params_method && arg_count != pd_count) {
				ec.Report.Error (1593, loc, "Delegate `{0}' does not take `{1}' arguments",
					TypeManager.CSharpName (del_type), arg_count.ToString ());
			} else if (arguments == null || !arguments.HasDynamic) {
				me.VerifyArgumentsCompat (ec, ref arguments, arg_count, mb,
					is_params_applicable || (!is_applicable && params_method), false, loc);
			}

			type = TypeManager.TypeToCoreType (method.ReturnType);
			eclass = ExprClass.Value;
			return this;
		}

		public override void Emit (EmitContext ec)
		{
			//
			// Invocation on delegates call the virtual Invoke member
			// so we are always `instance' calls
			//
			Invocation.EmitCall (ec, false, InstanceExpr, method, arguments, loc);
		}

		public override void EmitStatement (EmitContext ec)
		{
			Emit (ec);
			// 
			// Pop the return value if there is one
			//
			if (type != TypeManager.void_type)
				ec.ig.Emit (OpCodes.Pop);
		}

		public override System.Linq.Expressions.Expression MakeExpression (BuilderContext ctx)
		{
			return Invocation.MakeExpression (ctx, InstanceExpr, method, arguments);
		}

		public override void MutateHoistedGenericType (AnonymousMethodStorey storey)
		{
			storey.MutateGenericMethod (method);
			type = storey.MutateType (type);

			if (arguments != null)
				arguments.MutateHoistedGenericType (storey);

			InstanceExpr.MutateHoistedGenericType (storey);
		}
	}
}
