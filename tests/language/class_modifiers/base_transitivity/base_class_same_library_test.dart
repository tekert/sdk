// Copyright (c) 2023, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

// SharedOptions=--enable-experiment=class-modifiers

/// Test the valid uses of a base class within the same library

base class BaseClass {}

mixin _MixinOnObject {}

/// BaseClass can be extended, so long as the subtype is base, final
/// or sealed.

// Simple extension.

base class BaseExtend extends BaseClass {}

final class FinalExtend extends BaseClass {}

// Extending with a sealed class.

sealed class SealedExtend extends BaseClass {}

// Extending through a sealed class.

base class BaseSealedExtendExtend extends SealedExtend {}

final class FinalSealedExtendExtend extends SealedExtend {}

sealed class SealedSealedExtendExtend extends SealedExtend {}

// Implementing through a sealed class.

base class BaseSealedExtendImplement implements SealedExtend {}

final class FinalSealedExtendImplement implements SealedExtend {}

sealed class SealedSealedExtendImplement implements SealedExtend {}

base mixin class BaseMixinClassSealedExtendImplement implements SealedExtend {}

base mixin BaseMixinSealedExtendImplement implements SealedExtend {}

// Using a sealed class as an `on` type

base mixin BaseMixinSealedExtendOn on SealedExtend {}

// Extending via an anonymous mixin class.

base class BaseExtendWith extends BaseClass with _MixinOnObject {}

final class FinalExtendWith extends BaseClass with _MixinOnObject {}

sealed class SealedExtendWith extends BaseClass with _MixinOnObject {}

// Extending via an anonymous mixin application class.

final class FinalExtendApplication = BaseClass with _MixinOnObject;
base class BaseExtendApplication = BaseClass with _MixinOnObject;
sealed class SealedExtendApplication = BaseClass with _MixinOnObject;

/// BaseClass can be implemented, so long as the subtype is base, final, or
/// sealed

// Simple implementation.

base class BaseImplement implements BaseClass {}

final class FinalImplement implements BaseClass {}

// Implementing with a sealed class.

sealed class SealedImplement implements BaseClass {}

// Extending through a sealed class.

base class BaseSealedImplementExtend extends SealedImplement {}

final class FinalSealedImplementExtend extends SealedImplement {}

sealed class SealedSealedImplementExtend extends SealedImplement {}

// Implementing through a sealed class.

base class BaseSealedImplementImplement implements SealedImplement {}

final class FinalSealedImplementImplement implements SealedImplement {}

sealed class SealedSealedImplementImplement implements SealedImplement {}

// Implementing with a mixin class.

base mixin class BaseMixinClassImplement implements BaseClass {}

// Implementing by applying a mixin class.

base class BaseMixinClassImplementApplied extends Object
    with BaseMixinClassImplement {}

final class FinalMixinClassImplementApplied extends Object
    with BaseMixinClassImplement {}

sealed class SealedMixinClassImplementApplied extends Object
    with BaseMixinClassImplement {}

// Implementing with a mixin application class.

base class BaseImplementApplication = Object
    with _MixinOnObject
    implements BaseClass;
final class FinalImplementApplication = Object
    with _MixinOnObject
    implements BaseClass;
sealed class SealedImplementApplication = Object
    with _MixinOnObject
    implements BaseClass;

// Implementing with a mixin.

base mixin BaseMixinImplement implements BaseClass {}

// Implementing by applying a mixin.

base class BaseMixinImplementApplied extends Object with BaseMixinImplement {}

final class FinalMixinImplementApplied extends Object with BaseMixinImplement {}

sealed class SealedMixinImplementApplied extends Object
    with BaseMixinImplement {}

/// BaseClass can be an `on` type, so long as the subtype is base.

base mixin BaseMixinOn on BaseClass {}

// This test is intended just to check that certain combinations of modifiers
// are statically allowed.  Make this a static error test so that backends don't
// try to run it.
int x = "This is a static error test";
//      ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
// [analyzer] COMPILE_TIME_ERROR.INVALID_ASSIGNMENT
// [cfe] A value of type 'String' can't be assigned to a variable of type 'int'.
