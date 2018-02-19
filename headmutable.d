import std.traits;
import std.meta : staticIndexOf, AliasSeq;
import std.typecons : rebindable, Rebindable;

/**
 * Strips one level of const/immutable from a value, giving a head-mutable, reassignable value.
 *
 * Params:
 *   value = the value to convert.
 *
 * Returns:
 *   A head-mutable version of the passed value.
 */
public auto headMutable(T)(T value)
{
    static if (isPointer!T)
    {
        // T is a pointer, and decays naturally.
        return value;
    }
    else static if (isDynamicArray!T)
    {
        // T is a dynamic array, and decays naturally.
        return value;
    }
    else static if (!hasAliasing!(Unqual!T))
    {
        // T is a POD datatype - either a built-in type, or a struct with only POD members.
        return cast(Unqual!T)value;
    }
    else static if (is(T == class))
    {
        // Classes are reference types, so only the reference to it may be made head-mutable.
        return rebindable(value);
    }
    else static if (isAssociativeArray!T)
    {
        // AAs are reference types, so only the reference to it may be made head-mutable.
        return rebindable(value);
    }
    else static if (is(typeof(headMutableImpl(value))))
    {
        return headMutableImpl(value);
    }
    else
    {
        static assert(false, "Type "~T.stringof~" cannot be made head-mutable.");
    }
}

///
@safe unittest
{
    const a = [1,2,3];
    const(int)[] b = a.headMutable;
    assert(!is(typeof(a) == typeof(b)));
}

/// Default implementation of headMutable() for types that don't define their own.
private auto headMutableImpl(T)(T value)
{
    // Check if Tmp!Args is a valid type, and if so, if it has a field of type F.
    template hasFieldOfType(F, alias Tmp, Args...)
    {
        static if (is(Tmp!Args))
        {
            enum hasFieldOfType = staticIndexOf!(F, Fields!(Tmp!Args)) >= 0;
        }
        else
        {
            enum hasFieldOfType = false;
        }
    }

    auto impl(size_t index, Args...)()
    {
        static if (index >= Args.length)
        {
            static assert(false, "Type "~T.stringof~" cannot be made head-mutable.");
        }
        else static if (!is(Args[index]))
        {
            return impl!(index+1, Args);
        }
        else
        {
            alias Head = Args[0..index     ];
            alias Arg  = Args[   index     ];
            alias Tail = Args[   index+1..$];

            alias NewArgs1 = AliasSeq!(Head, HeadMutable!(Arg, T),        Tail);
            alias NewArgs2 = AliasSeq!(Head, CopyTypeQualifiers!(T, Arg), Tail);

            // Try the simplest possible type first - if we can get away with marking only a single parameter const, all the better.
            static if (is(typeof(impl!(index+1, Args)())))
            {
                return impl!(index+1, Args)();
            // If that failed, try a version with one more parameter as head-mutable.
            }
            else static if (is(typeof(impl!(index+1, NewArgs1)())))
            {
                return impl!(index+1, NewArgs1)();
            // If *that* failed, try a version with one more parameter as const.
            }
            else static if (is(typeof(impl!(index+1, NewArgs2)())) && !is(NewArgs2 == Args))
            {
                return impl!(index+1, NewArgs2)();
            // All the above had too much const, or otherwise didn't work. Or we're just at the end of the argument list.
            }
            else
            {
                alias Tmp = TemplateOf!T;

                // If T has a field of type Arg, and the new type has a field of type HeadMutable!Arg, we've found the right argument.
                static if (hasFieldOfType!(Arg, Tmp, TemplateArgsOf!T) && 
                           hasFieldOfType!(HeadMutable!(Arg, T), Tmp, NewArgs1) &&
                           !is(Args == NewArgs1))
                {
                    alias NewType = Tmp!NewArgs1;
                }
                // If not, try marking one argument as const, and work from there.
                else static if (is(Tmp!NewArgs2) && !is(Args == NewArgs2))
                {
                    alias NewType = Tmp!NewArgs2;
                }
                else
                {
                    static assert(false, "Type "~T.stringof~" cannot be made head-mutable.");
                }

                // Can we construct our new type from the original?
                static if (is(typeof({ NewType a = value; })))
                {
                    return NewType(value);
                }
                // If not, is at least one of the earlier arguments marked const?
                else static if (!is(Args == TemplateArgsOf!T) && is(typeof({ Tmp!Args a = value; })))
                {
                    return Tmp!Args(value);
                }
                else
                {
                    static assert(false, "Type "~T.stringof~" cannot be made head-mutable.");
                }
            }
        }
    }
    return impl!(0, TemplateArgsOf!T);
}

/**
 * Strips one level of const/immutable from a type, giving a head-mutable, reassignable type.
 *
 * Params:
 *   T = The type from which to generate a head-mutable version.
 *
 * Returns:
 *   The type that corresponds to a head-mutable version of T.
 *
 */
public alias HeadMutable(T) = typeof(T.init.headMutable());
/// Ditto
public alias HeadMutable(T, ConstSource) = HeadMutable!(CopyTypeQualifiers!(ConstSource, T));

///
@safe unittest
{
    static assert(is(HeadMutable!(const(int[])) == const(int)[]));
    
    class A {}
    static assert(is(HeadMutable!(const(A)) == Rebindable!(const(A))));
    
    static struct S(T) {
        T arr;
        this(T2)(const S!(T2) rhs) {}
    }
    static assert(is(HeadMutable!(const(S!(int[]))) == S!(const(int)[])));
}

struct S4(T1, T2, T3) if (is(CopyTypeQualifiers!(T1, T3) == T3) && is(CopyTypeQualifiers!(T3, T1) == T1))
{
    T2[] arr;
    this(Ti1, Ti3)(const S4!(Ti1, T2, Ti3) rhs) {}
}

unittest
{
    const S4!(int, int[], int) a;
    auto b = a.headMutable;
    static assert(is(typeof(b) == S4!(const int, int[], const int)));
}

struct S3(alias fn, T)
{
    T[] arr;
    this(T2)(const S3!(fn, T2) rhs) if (is(const(T) == const(T2))) {}
}

unittest
{
    const S3!("foo", int) a;
    auto b = a.headMutable;
    static assert(is(typeof(b) == S3!("foo", const(int))));
}

struct S1(T)
{
    T arr;
    this(T2)(const S1!(T2) rhs) if (is(const(T) == const(T2))) {}
}

unittest
{
    const S1!(int[]) a;
    auto b = a.headMutableImpl;
    static assert(is(typeof(b) == S1!(const(int)[])));
}

struct S2(T)
{
    T[] arr;
    this(T2)(const S2!(T2) rhs) if (is(const(T) == const(T2))) {}
}

unittest
{
    const S2!int a;
    S2!(const int) b = a;
    auto c = a.headMutable;
    static assert(is(typeof(b) == typeof(c)));
}

unittest
{
    const S2!(int[]) a;
    auto b = a.headMutable;
    static assert(is(typeof(b) == S2!(const int[])));
}

void main() {}