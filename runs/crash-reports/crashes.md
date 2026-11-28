# TestFlight に届いたクラッシュ（新しい順）

## 1. 2026-11-15T02:59:46.427Z  ビルド 1.0.6 (1094)
- deviceModel: iPad16_3
- deviceFamily: IPAD
- osVersion: 26.6.1
- appPlatform: IOS
- architecture: arm64e
- locale: ja-TW
- diskBytesAvailable: 162313621504
- batteryPercentage: 25
- screenWidthInPoints: 1210
- screenHeightInPoints: 834
- buildBundleId: com.nori.catchwords
- comment: （45 文字。公開しない）

```
Incident Identifier: 7C1586CD-841C-436E-BB2D-E9D6A38A3FFF
Distributor ID:      com.apple.TestFlight
Hardware Model:      iPad16,3
Process:             CatchWords [37342]
Path:                /private/var/containers/Bundle/Application/37DCD888-40C0-446B-AC01-3503A4B071A6/CatchWords.app/CatchWords
Identifier:          com.nori.catchwords
Version:             1.0.6 (1094)
AppStoreTools:       27B52
AppVariant:          1:iPad16,3-A:26
Beta:                YES
Code Type:           ARM-64 (Native)
Role:                Foreground
Parent Process:      launchd [1]
Coalition:           com.nori.catchwords [741]

Date/Time:           2026-11-15 10:59:07.6831 +0800
Launch Time:         2026-11-13 22:00:29.4510 +0800
OS Version:          iPhone OS 26.6.1 (23G83)
Release Type:        User
Report Version:      104

Exception Type:  EXC_CRASH (SIGABRT)
Exception Codes: 0x0000000000000000, 0x0000000000000000
Termination Reason: SIGNAL 6 Abort trap: 6
Terminating Process: CatchWords [37342]

Triggered by Thread:  23

Last Exception Backtrace:
0   CoreFoundation                	0x19df542d4 __exceptionPreprocess + 164 (:-1)
1   libobjc.A.dylib               	0x19aa21224 objc_exception_throw + 88 (:-1)
2   Foundation                    	0x19ba85520 -[NSAssertionHandler handleFailureInMethod:object:file:lineNumber:description:] + 288 (:-1)
3   UIKitCore                     	0x1a507c7ec -[UIApplication _performBlockAfterCATransactionCommitSynchronizes:] + 280 (:-1)
4   UIKitCore                     	0x1a5089ee8 -[UIApplication _updateStateRestorationArchiveForBackgroundEvent:saveState:exitIfCouldNotRestoreState:updateSnapshot:windowScene:] + 528 (:-1)
5   UIKitCore                     	0x1a508a29c -[UIApplication _updateSnapshotAndStateRestorationWithAction:windowScene:] + 144 (:-1)
6   CatchWords                    	0x10259a278 @objc closure #1 in NotificationRouter.userNotificationCenter(_:didReceive:) + 76 (/<compiler-generated>:0)
7   CatchWords                    	0x102440859 <deduplicated_symbol> + 1
8   CatchWords                    	0x1024cd661 <deduplicated_symbol> + 1
9   CatchWords                    	0x102440859 <deduplicated_symbol> + 1
10  CatchWords                    	0x1024cd661 <deduplicated_symbol> + 1
11  CatchWords                    	0x1024caae9 <deduplicated_symbol> + 1
12  CatchWords                    	0x1024cd661 <deduplicated_symbol> + 1
13  libswift_Concurrency.dylib    	0x19bf5f385 completeTaskWithClosure(swift::AsyncContext*, swift::SwiftError*) + 1 (:-1)

Thread 0 name:
Thread 0:
0   libswiftCore.dylib            	0x000000019ab3b9d8 _dispatch_once_f(long*, void*, void (*)(void*)) + 4 (:-1)
1   libswiftCore.dylib            	0x000000019ab3b9d8 swift::threading_impl::once_impl(long&, void (*)(void*), void*) + 4 (:-1)
2   libswiftCore.dylib            	0x000000019ab3b9d8 swift::once(long&, void (*)(void*), void*) + 4 (:-1)
3   libswiftCore.dylib            	0x000000019ab3b9d8 swift::Lazy<swift::MetadataCache<(anonymous namespace)::WitnessTableCacheEntry, (unsigned short)16>>::get(void (*)(void*)) + 4 (:-1)
4   libswiftCore.dylib            	0x000000019ab3b9d8 getCache(swift::TargetGenericWitnessTable<swift::InProcess> const*) + 184 (:-1)
5   libswiftCore.dylib            	0x000000019ab3b9d8 swift::_getWitnessTable(swift::TargetProtocolConformanceDescriptor<swift::InProcess> const*, swift::TargetMetadata<swift::InProcess> const*, void const* const*) + 904 (:-1)
6   SwiftUI                       	0x00000001a6fa0254 specialized Attribute.init<A>(_:) + 88 (:-1)
7   SwiftUI                       	0x00000001a6fa0254 static SystemScrollView._makeView(view:inputs:) + 6736 (:-1)
8   SwiftUICore                   	0x00000001a81dd324 specialized static View.makeDebuggableView(view:inputs:) + 36 (:-1)
9   SwiftUICore                   	0x00000001a81dd324 closure #2 in static ModifiedContent<>._makeView(view:inputs:) + 380 (:-1)
10  SwiftUICore                   	0x00000001a829074c <deduplicated_symbol> + 68 (:-1)
11  SwiftUICore                   	0x00000001a828da8c specialized static ViewModifier.makeDebuggableView(modifier:inputs:body:) + 40 (:-1)
12  SwiftUICore                   	0x00000001a828da8c static StaticIf<>._makeView(modifier:inputs:body:) + 912 (:-1)
13  SwiftUICore                   	0x00000001a828db40 protocol witness for static ViewModifier._makeView(modifier:inputs:body:) in conformance <> StaticIf<A, B, C> + 44 (:-1)
14  SwiftUICore                   	0x00000001a81dd124 specialized static ViewModifier.makeDebuggableView(modifier:inputs:body:) + 60 (:-1)
15  SwiftUICore                   	0x00000001a81dd124 static ModifiedContent<>._makeView(view:inputs:) + 452 (:-1)
16  SwiftUICore                   	0x00000001a81dd324 specialized static View.makeDebuggableView(view:inputs:) + 36 (:-1)
17  SwiftUICore                   	0x00000001a81dd324 closure #2 in static ModifiedContent<>._makeView(view:inputs:) + 380 (:-1)
18  SwiftUI                       	0x00000001a6f9e120 specialized static ViewModifier<>._makeView(modifier:inputs:body:) + 28 (:-1)
19  SwiftUI                       	0x00000001a6f9e120 protocol witness for static ViewModifier._makeView(modifier:inputs:body:) in conformance ResolvedScrollBehaviorModifier + 152 (:-1)
20  SwiftUICore                   	0x00000001a81dd124 specialized static ViewModifier.makeDebuggableView(modifier:inputs:body:) + 60 (:-1)
21  SwiftUICore                   	0x00000001a81dd124 static ModifiedContent<>._makeView(view:inputs:) + 452 (:-1)
22  SwiftUICore                   	0x00000001a81dd324 specialized static View.makeDebuggableView(view:inputs:) + 36 (:-1)
23  SwiftUICore                   	0x00000001a81dd324 closure #2 in static ModifiedContent<>._makeView(view:inputs:) + 380 (:-1)
24  SwiftUICore                   	0x00000001a8333064 static ScrollPhaseStateConfigurationModifier._makeView(modifier:inputs:body:) + 232 (:-1)
25  SwiftUICore                   	0x00000001a81dd124 specialized static ViewModifier.makeDebuggableView(modifier:inputs:body:) + 60 (:-1)
26  SwiftUICore                   	0x00000001a81dd124 static ModifiedContent<>._makeView(view:inputs:) + 452 (:-1)
46  SwiftUICore                   	0x00000001a81dd324 specialized static View.makeDebuggableView(view:inputs:) + 36 (:-1)
47  SwiftUICore                   	0x00000001a81dd324 closure #2 in static ModifiedContent<>._makeView(view:inputs:) + 380 (:-1)
48  SwiftUICore                   	0x00000001a81f0318 static _AppearanceActionModifier._makeView(modifier:inputs:body:) + 288 (:-1)
49  SwiftUICore                   	0x00000001a81dd124 specialized static ViewModifier.makeDebuggableView(modifier:inputs:body:) + 60 (:-1)
50  SwiftUICore                   	0x00000001a81dd124 static ModifiedContent<>._makeView(view:inputs:) + 452 (:-1)
51  SwiftUICore                   	0x00000001a81dd324 specialized static View.makeDebuggableView(view:inputs:) + 36 (:-1)
52  SwiftUICore                   	0x00000001a81dd324 closure #2 in static ModifiedContent<>._makeView(view:inputs:) + 380 (:-1)
53  SwiftUICore                   	0x00000001a8280af4 static _ValueActionModifier._makeView(modifier:inputs:body:) + 472
54  SwiftUICore                   	0x00000001a8280b90 static _ValueActionModifier2._makeView(modifier:inputs:body:) + 96 (:-1)
55  SwiftUICore                   	0x00000001a81dd124 specialized static ViewModifier.makeDebuggableView(modifier:inputs:body:) + 60 (:-1)
56  SwiftUICore                   	0x00000001a81dd124 static ModifiedContent<>._makeView(view:inputs:) + 452 (:-1)
57  SwiftUICore                   	0x00000001a81dd324 specialized static View.makeDebuggableView(view:inputs:) + 36 (:-1)
58  SwiftUICore                   	0x00000001a81dd324 closure #2 in static ModifiedContent<>._makeView(view:inputs:) + 380 (:-1)
59  SwiftUICore                   	0x00000001a81f0318 static _AppearanceActionModifier._makeView(modifier:inputs:body:) + 288 (:-1)
60  SwiftUICore                   	0x00000001a81dd124 specialized static ViewModifier.makeDebuggableView(modifier:inputs:body:) + 60 (:-1)
61  SwiftUICore                   	0x00000001a81dd124 static ModifiedContent<>._makeView(view:inputs:) + 452 (:-1)
62  SwiftUICore                   	0x00000001a833cf30 specialized static View.makeDebuggableView(view:inputs:) + 36 (:-1)
63  SwiftUICore                   	0x00000001a833cf30 static _DelayedPreferenceView._makeView(view:inputs:) + 752 (:-1)
64  SwiftUICore                   	0x00000001a81e09d4 specialized static View.makeDebuggableView(view:inputs:) + 36 (:-1)
65  SwiftUICore                   	0x00000001a81e09d4 project #1 <A>(_:) in TypedUnaryViewGenerator.makeView(inputs:indirectMap:) + 340 (:-1)
66  SwiftUICore                   	0x00000001a81e0868 TypedUnaryViewGenerator.makeView(inputs:indirectMap:) + 112 (:-1)
67  SwiftUICore                   	0x00000001a81e0868 protocol witness for UnaryViewGenerator.makeView(inputs:indirectMap:) in conformance TypedUnaryViewGenerator + 156 (:-1)
68  SwiftUICore                   	0x00000001a81e0f78 closure #1 in UnaryElements.makeElements(from:inputs:indirectMap:body:) + 312 (:-1)
69  SwiftUICore                   	0x00000001a81e25dc closure #2 in static Layout.makeStaticView(root:inputs:properties:list:) + 340 (:-1)
70  SwiftUICore                   	0x00000001a81e1a24 thunk for @callee_guaranteed (@in_guaranteed _ViewInputs, @guaranteed @escaping @callee_guaranteed (@in_guaranteed _ViewInputs) -> (@out _ViewOutputs)) -> (@out _ViewOutputs?) + 28 (:-1)
71  SwiftUICore                   	0x00000001a81e19f4 closure #1 in closure #1 in _ViewList_Elements.makeAllElements(inputs:indirectMap:body:) + 80 (:-1)
72  SwiftUICore                   	0x00000001a81e1700 UnaryElements.makeElements(from:inputs:indirectMap:body:) + 400 (:-1)
73  SwiftUICore                   	0x00000001a81e43f0 MergedElements.makeElements(from:inputs:indirectMap:body:) + 344 (:-1)
74  SwiftUICore                   	0x00000001a81e488c protocol witness for _ViewList_Elements.makeElements(from:inputs:indirectMap:body:) in conformance MergedElements + 32 (:-1)
75  SwiftUICore                   	0x00000001a8323280 specialized closure #1 in _ViewList_Elements.makeAllElements(inputs:indirectMap:body:) + 156 (:-1)
76  SwiftUICore                   	0x00000001a8323280 specialized _ViewList_Elements.makeAllElements(inputs:indirectMap:body:) + 204 (:-1)
77  SwiftUICore                   	0x00000001a8323280 specialized _ViewList_Elements.makeAllElements(inputs:body:) + 204 (:-1)
78  SwiftUICore                   	0x00000001a8323280 specialized static Layout.makeStaticView(root:inputs:properties:list:) + 812 (:-1)
79  SwiftUICore                   	0x00000001a81f658c specialized static Layout.makeLayoutView(root:inputs:body:) + 548 (:-1)
80  SwiftUICore                   	0x00000001a81f6738 specialized static Layout._makeLayoutView(root:inputs:body:) + 8 (:-1)
81  SwiftUICore                   	0x00000001a81f6738 static _ZStackLayout._makeView(root:inputs:body:) + 44 (:-1)
82  SwiftUICore                   	0x00000001a81f6738 protocol witness for static _VariadicView_ViewRoot._makeView(root:inputs:body:) in conformance _ZStackLayout + 60 (:-1)
83  SwiftUICore                   	0x00000001a81d9fb8 static _VariadicView.Tree<>._makeView(view:inputs:) + 388 (:-1)
84  SwiftUICore                   	0x00000001a8276df8 specialized protocol witness for static View._makeView(view:inputs:) in conformance <> _VariadicView.Tree<A, B> + 40 (:-1)
85  SwiftUICore                   	0x00000001a8276df8 specialized static View.makeDebuggableView(view:inputs:) + 40 (:-1)
86  SwiftUICore                   	0x00000001a8276df8 specialized static _VariadicView.Tree<>.makePlatformSubstitutableView(view:inputs:) + 40 (:-1)
87  SwiftUICore                   	0x00000001a8276df8 static ZStack._makeView(view:inputs:) + 412 (:-1)
88  SwiftUICore                   	0x00000001a81e09d4 specialized static View.makeDebuggableView(view:inputs:) + 36 (:-1)
89  SwiftUICore                   	0x00000001a81e09d4 project #1 <A>(_:) in TypedUnaryViewGenerator.makeView(inputs:indirectMap:) + 340 (:-1)
90  SwiftUICore                   	0x00000001a81e0868 TypedUnaryViewGenerator.makeView(inputs:indirectMap:) + 112 (:-1)
91  SwiftUICore                   	0x00000001a81e0868 protocol witness for UnaryViewGenerator.makeView(inputs:indirectMap:) in conformance TypedUnaryViewGenerator + 156 (:-1)
92  SwiftUICore                   	0x00000001a81e0f78 closure #1 in UnaryElements.makeElements(from:inputs:indirectMap:body:) + 312 (:-1)
93  SwiftUICore                   	0x00000001a81e1f9c <deduplicated_symbol> + 68 (:-1)
94  SwiftUI                       	0x00000001a707efd4 specialized static ViewInputsModifier._makeView(modifier:inputs:body:) + 48 (:-1)
95  SwiftUI                       	0x00000001a707efd4 protocol witness for static ViewModifier._makeView(modifier:inputs:body:) in conformance CoordinateSpaceNameModifier + 200
96  SwiftUICore                   	0x00000001a81e1334 specialized static ViewModifier.makeDebuggableView(modifier:inputs:body:) + 60 (:-1)
97  SwiftUICore                   	0x00000001a81e1334 specialized project #1 <A>(_:) in closure #1 in closure #1 in closure #1 in ModifiedElements.makeElements(from:inputs:indirectMap:body:) + 476 (:-1)
98  SwiftUICore                   	0x00000001a81e1540 closure #1 in closure #1 in closure #1 in ModifiedElements.makeElements(from:inputs:indirectMap:body:) + 340 (:-1)
99  SwiftUICore                   	0x00000001a81e1f9c <deduplicated_symbol> + 68 (:-1)
100 SwiftUICore                   	0x00000001a81f680c makeSecondaryLayerView<A>(secondaryLayer:alignment:inputs:body:flipOrder:) + 200 (:-1)
101 SwiftUICore                   	0x00000001a825463c static _OverlayModifier._makeView(modifier:inputs:body:) + 248 (:-1)
102 SwiftUICore                   	0x00000001a81e1334 specialized static ViewModifier.makeDebuggableView(modifier:inputs:body:) + 60 (:-1)
103 SwiftUICore                   	0x00000001a81e1334 specialized project #1 <A>(_:) in closure #1 in closure #1 in closure #1 in ModifiedElements.makeElements(from:inputs:indirectMap:body:) + 476 (:-1)
104 SwiftUICore                   	0x00000001a81e1540 closure #1 in closure #1 in closure #1 in ModifiedElements.makeElements(from:inputs:indirectMap:body:) + 340 (:-1)
105 SwiftUICore                   	0x00000001a81e1f9c <deduplicated_symbol> + 68 (:-1)
172 SwiftUICore                   	0x00000001a8e5134c static _InsetViewModifier._makeView(modifier:inputs:body:) + 1144 (:-1)
173 SwiftUICore                   	0x00000001a81e1334 specialized static ViewModifier.makeDebuggableView(modifier:inputs:body:) + 60 (:-1)
174 SwiftUICore                   	0x00000001a81e1334 specialized project #1 <A>(_:) in closure #1 in closure #1 in closure #1 in ModifiedElements.makeElements(from:inputs:indirectMap:body:) + 476 (:-1)
175 SwiftUICore                   	0x00000001a81e1540 closure #1 in closure #1 in closure #1 in ModifiedElements.makeElements(from:inputs:indirectMap:body:) + 340 (:-1)
176 SwiftUICore                   	0x00000001a81e1f9c <deduplicated_symbol> + 68 (:-1)
177 SwiftUICore                   	0x00000001a8e5134c static _InsetViewModifier._makeView(modifier:inputs:body:) + 1144 (:-1)
178 SwiftUICore                   	0x00000001a81e1334 specialized static ViewModifier.makeDebuggableView(modifier:inputs:body:) + 60 (:-1)
179 SwiftUICore                   	0x00000001a81e1334 specialized project #1 <A>(_:) in closure #1 in closure #1 in closure #1 in ModifiedElements.makeElements(from:inputs:indirectMap:body:) + 476 (:-1)
180 SwiftUICore                   	0x00000001a81e1540 closure #1 in closure #1 in closure #1 in ModifiedElements.makeElements(from:inputs:indirectMap:body:) + 340 (:-1)
181 SwiftUICore                   	0x00000001a81e1f9c <deduplicated_symbol> + 68 (:-1)
182 SwiftUICore                   	0x00000001a8e5134c static _InsetViewModifier._makeView(modifier:inputs:body:) + 1144 (:-1)
183 SwiftUICore                   	0x00000001a81e1334 specialized static ViewModifier.makeDebuggableView(modifier:inputs:body:) + 60 (:-1)
184 SwiftUICore                   	0x00000001a81e1334 specialized project #1 <A>(_:) in closure #1 in closure #1 in closure #1 in ModifiedElements.makeElements(from:inputs:indirectMap:body:) + 476 (:-1)
185 SwiftUICore                   	0x00000001a81e1540 closure #1 in closure #1 in closure #1 in ModifiedElements.makeElements(from:inputs:indirectMap:body:) + 340 (:-1)
186 SwiftUICore                   	0x00000001a81e1f9c <deduplicated_symbol> + 68 (:-1)
187 SwiftUICore                   	0x00000001a81fb048 static ViewModifierContentProvider.providerMakeView(view:inputs:) + 620 (:-1)
188 SwiftUICore                   	0x00000001a8202d38 static PlaceholderContentView._makeView(view:inputs:) + 108 (:-1)
189 SwiftUICore                   	0x00000001a81dd324 specialized static View.makeDebuggableView(view:inputs:) + 36 (:-1)
190 SwiftUICore                   	0x00000001a81dd324 closure #2 in static ModifiedContent<>._makeView(view:inputs:) + 380 (:-1)
191 SwiftUICore                   	0x00000001a8204918 specialized static _RendererEffect._makeRendererEffect(effect:inputs:body:) + 240 (:-1)
192 SwiftUICore                   	0x00000001a87b7734 specialized static RendererEffect.makeRendererEffect(effect:inputs:body:) + 72 (:-1)
193 SwiftUICore                   	0x00000001a87b7734 static OpacityRendererEffect._makeView(modifier:inputs:body:) + 156 (:-1)
194 SwiftUICore                   	0x00000001a81dd124 specialized static ViewModifier.makeDebuggableView(modifier:inputs:body:) + 60 (:-1)
195 SwiftUICore                   	0x00000001a81dd124 static ModifiedContent<>._makeView(view:inputs:) + 452 (:-1)
196 SwiftUICore                   	0x00000001a82057d4 specialized static View.makeDebuggableView(view:inputs:) + 32 (:-1)
197 SwiftUICore                   	0x00000001a82057d4 static Transition.makeView(view:inputs:body:) + 476 (:-1)
198 SwiftUICore                   	0x00000001a82054ac DynamicLayoutViewAdaptor.MakeTransition.visit<A>(_:) + 1032 (:-1)
199 SwiftUICore                   	0x00000001a8205908 TransitionBox.visitBase<A>(applying:) + 120 (:-1)
200 SwiftUICore                   	0x00000001a8204284 specialized AnyTransition.visitBase<A>(applying:) + 32 (:-1)
201 SwiftUICore                   	0x00000001a8204284 closure #2 in DynamicLayoutViewAdaptor.makeItemLayout(item:uniqueId:inputs:containerInfo:containerInputs:) + 712 (:-1)
202 SwiftUICore                   	0x00000001a8205880 partial apply for closure #2 in DynamicLayoutViewAdaptor.makeItemLayout(item:uniqueId:inputs:containerInfo:containerInputs:) + 56 (:-1)
203 SwiftUICore                   	0x00000001a81e1a24 thunk for @callee_guaranteed (@in_guaranteed _ViewInputs, @guaranteed @escaping @callee_guaranteed (@in_guaranteed _ViewInputs) -> (@out _ViewOutputs)) -> (@out _ViewOutputs?) + 28 (:-1)
204 SwiftUICore                   	0x00000001a81e19f4 closure #1 in closure #1 in _ViewList_Elements.makeAllElements(inputs:indirectMap:body:) + 80 (:-1)
205 SwiftUICore                   	0x00000001a81e1c0c thunk for @callee_guaranteed (@in_guaranteed _ViewInputs, @guaranteed @escaping @callee_guaranteed (@in_guaranteed _ViewInputs) -> (@out _ViewOutputs)) -> (@out _ViewOutputs?, @unowned Bool) + 8 (:-1)
206 SwiftUICore                   	0x00000001a81e1c0c partial apply for thunk for @callee_guaranteed (@in_guaranteed _ViewInputs, @guaranteed @escaping @callee_guaranteed (@in_guaranteed _ViewInputs) -> (@out _ViewOutputs)) -> (@out _ViewOutputs?, @un... + 28 (:-1)
207 SwiftUICore                   	0x00000001a81e10b0 closure #1 in closure #1 in ModifiedElements.makeElements(from:inputs:indirectMap:body:) + 264 (:-1)
208 SwiftUICore                   	0x00000001a81e0c8c partial apply for closure #1 in closure #1 in ModifiedElements.makeElements(from:inputs:indirectMap:body:) + 36 (:-1)
209 SwiftUICore                   	0x00000001a81e1c0c thunk for @callee_guaranteed (@in_guaranteed _ViewInputs, @guaranteed @escaping @callee_guaranteed (@in_guaranteed _ViewInputs) -> (@out _ViewOutputs)) -> (@out _ViewOutputs?, @unowned Bool) + 8 (:-1)
210 SwiftUICore                   	0x00000001a81e1c0c partial apply for thunk for @callee_guaranteed (@in_guaranteed _ViewInputs, @guaranteed @escaping @callee_guaranteed (@in_guaranteed _ViewInputs) -> (@out _ViewOutputs)) -> (@out _ViewOutputs?, @un... + 28 (:-1)
211 SwiftUICore                   	0x00000001a81e10b0 closure #1 in closure #1 in ModifiedElements.makeElements(from:inputs:indirectMap:body:) + 264 (:-1)
212 SwiftUICore                   	0x00000001a81e0c8c partial apply for closure #1 in closure #1 in ModifiedElements.makeElements(from:inputs:indirectMap:body:) + 36 (:-1)
213 SwiftUICore                   	0x00000001a81e1c0c thunk for @callee_guaranteed (@in_guaranteed _ViewInputs, @guaranteed @escaping @callee_guaranteed (@in_guaranteed _ViewInputs) -> (@out _ViewOutputs)) -> (@out _ViewOutputs?, @unowned Bool) + 8 (:-1)
214 SwiftUICore                   	0x00000001a81e1c0c partial apply for thunk for @callee_guaranteed (@in_guaranteed _ViewInputs, @guaranteed @escaping @callee_guaranteed (@in_guaranteed _ViewInputs) -> (@out _ViewOutputs)) -> (@out _ViewOutputs?, @un... + 28 (:-1)
215 SwiftUICore                   	0x00000001a81e10b0 closure #1 in closure #1 in ModifiedElements.makeElements(from:inputs:indirectMap:body:) + 264 (:-1)
216 SwiftUICore                   	0x00000001a81e0c8c partial apply for closure #1 in closure #1 in ModifiedElements.makeElements(from:inputs:indirectMap:body:) + 36 (:-1)
262 SwiftUICore                   	0x00000001a81e1c0c thunk for @callee_guaranteed (@in_guaranteed _ViewInputs, @guaranteed @escaping @callee_guaranteed (@in_guaranteed _ViewInputs) -> (@out _ViewOutputs)) -> (@out _ViewOutputs?, @unowned Bool) + 8 (:-1)
263 SwiftUICore                   	0x00000001a81e1c0c partial apply for thunk for @callee_guaranteed (@in_guaranteed _ViewInputs, @guaranteed @escaping @callee_guaranteed (@in_guaranteed _ViewInputs) -> (@out _ViewOutputs)) -> (@out _ViewOutputs?, @un... + 28 (:-1)
264 SwiftUICore                   	0x00000001a81e10b0 closure #1 in closure #1 in ModifiedElements.makeElements(from:inputs:indirectMap:body:) + 264 (:-1)
265 SwiftUICore                   	0x00000001a81e0c8c partial apply for closure #1 in closure #1 in ModifiedElements.makeElements(from:inputs:indirectMap:body:) + 36 (:-1)
266 SwiftUICore                   	0x00000001a81e1c0c thunk for @callee_guaranteed (@in_guaranteed _ViewInputs, @guaranteed @escaping @callee_guaranteed (@in_guaranteed _ViewInputs) -> (@out _ViewOutputs)) -> (@out _ViewOutputs?, @unowned Bool) + 8 (:-1)
267 SwiftUICore                   	0x00000001a81e1c0c partial apply for thunk for @callee_guaranteed (@in_guaranteed _ViewInputs, @guaranteed @escaping @callee_guaranteed (@in_guaranteed _ViewInputs) -> (@out _ViewOutputs)) -> (@out _ViewOutputs?, @un... + 28 (:-1)
268 SwiftUICore                   	0x00000001a81e10b0 closure #1 in closure #1 in ModifiedElements.makeElements(from:inputs:indirectMap:body:) + 264 (:-1)
269 SwiftUICore                   	0x00000001a81e0c8c partial apply for closure #1 in closure #1 in ModifiedElements.makeElements(from:inputs:indirectMap:body:) + 36 (:-1)
270 SwiftUICore                   	0x00000001a81e1c0c thunk for @callee_guaranteed (@in_guaranteed _ViewInputs, @guaranteed @escaping @callee_guaranteed (@in_guaranteed _ViewInputs) -> (@out _ViewOutputs)) -> (@out _ViewOutputs?, @unowned Bool) + 8 (:-1)
271 SwiftUICore                   	0x00000001a81e1c0c partial apply for thunk for @callee_guaranteed (@in_guaranteed _ViewInputs, @guaranteed @escaping @callee_guaranteed (@in_guaranteed _ViewInputs) -> (@out _ViewOutputs)) -> (@out _ViewOutputs?, @un... + 28 (:-1)
272 SwiftUICore                   	0x00000001a81e10b0 closure #1 in closure #1 in ModifiedElements.makeElements(from:inputs:indirectMap:body:) + 264 (:-1)
273 SwiftUICore                   	0x00000001a81e0c8c partial apply for closure #1 in closure #1 in ModifiedElements.makeElements(from:inputs:indirectMap:body:) + 36 (:-1)
274 SwiftUICore                   	0x00000001a81e1700 UnaryElements.makeElements(from:inputs:indirectMap:body:) + 400 (:-1)
275 SwiftUICore                   	0x00000001a81e1b90 closure #1 in ModifiedElements.makeElements(from:inputs:indirectMap:body:) + 124 (:-1)
276 SwiftUICore                   	0x00000001a81e1b90 ModifiedElements.makeElements(from:inputs:indirectMap:body:) + 208 (:-1)
277 SwiftUICore                   	0x00000001a81e1b90 protocol witness for _ViewList_Elements.makeElements(from:inputs:indirectMap:body:) in conformance ModifiedElements + 268 (:-1)
293 SwiftUICore                   	0x00000001a8207120 specialized closure #1 in DynamicContainerInfo.updateItems(disableTransitions:) + 2420 (:-1)
294 SwiftUICore                   	0x00000001a82076e4 closure #1 in DynamicLayoutViewAdaptor.foreachItem(items:_:) + 124 (:-1)
295 SwiftUICore                   	0x00000001a81ff898 _ViewList_Node.applySublists(from:style:transform:to:) + 644 (:-1)
296 SwiftUICore                   	0x00000001a81ffdc0 partial apply for closure #1 in _ViewList_Node.applySublists(from:style:transform:to:) + 72 (:-1)
297 SwiftUICore                   	0x00000001a8200184 BaseViewList.applyNodes(from:style:list:transform:to:) + 328 (:-1)
298 SwiftUICore                   	0x00000001a89bc82c closure #1 in ModifiedViewList.applyNodes(from:style:list:transform:to:) + 48 (:-1)
299 SwiftUICore                   	0x00000001a89bc82c specialized closure #1 in _ViewList_TemporarySublistTransform.withPushedItem<A, B>(_:do:) + 48 (:-1)
300 SwiftUICore                   	0x00000001a89bc82c specialized closure #1 in _ViewList_TemporarySublistTransform.withPushedItem<A, B>(_:do:) + 48 (:-1)
301 SwiftUICore                   	0x00000001a89bc82c specialized withUnsafeMutablePointer<A, B, C>(to:_:) + 48 (:-1)
302 SwiftUICore                   	0x00000001a89bc82c specialized _ViewList_TemporarySublistTransform.withPushedItem<A, B>(_:do:) + 48 (:-1)
303 SwiftUICore                   	0x00000001a89bc82c ModifiedViewList.applyNodes(from:style:list:transform:to:) + 472 (:-1)
325 SwiftUICore                   	0x00000001a81ff7f4 _ViewList_Group.applyNodes(from:style:transform:to:) + 180 (:-1)
326 SwiftUICore                   	0x00000001a81ff7f4 _ViewList_Node.applySublists(from:style:transform:to:) + 480 (:-1)
327 SwiftUICore                   	0x00000001a81ffdc0 partial apply for closure #1 in _ViewList_Node.applySublists(from:style:transform:to:) + 72 (:-1)
328 SwiftUICore                   	0x00000001a81f7640 _ViewList_Group.applyNodes(from:style:list:transform:to:) + 72 (:-1)
329 SwiftUICore                   	0x00000001a81f7640 protocol witness for ViewList.applyNodes(from:style:list:transform:to:) in conformance _ViewList_Group + 108 (:-1)
330 SwiftUICore                   	0x00000001a81d4578 ViewList.applySublists(from:style:list:transform:to:) + 20 (:-1)
331 SwiftUICore                   	0x00000001a81d4578 ViewList.applySublists(from:style:list:to:) + 20 (:-1)
332 SwiftUICore                   	0x00000001a81d4578 ViewList.applySublists(from:list:to:) + 104 (:-1)
333 SwiftUICore                   	0x00000001a81d4b0c DynamicLayoutViewAdaptor.foreachItem(items:_:) + 48 (:-1)
334 SwiftUICore                   	0x00000001a81d4b0c protocol witness for DynamicContainerAdaptor.foreachItem(items:_:) in conformance DynamicLayoutViewAdaptor + 48 (:-1)
335 SwiftUICore                   	0x00000001a81d4b0c specialized DynamicContainerInfo.updateItems(disableTransitions:) + 412 (:-1)
336 SwiftUICore                   	0x00000001a81d5978 specialized DynamicContainerInfo.updateValue() + 452 (:-1)
337 SwiftUICore                   	0x00000001a8b821a8 specialized protocol witness for StatefulRule.updateValue() in conformance DynamicContainerInfo<A> + 8 (:-1)
338 SwiftUICore                   	0x00000001a8b821a8 specialized implicit closure #1 in closure #1 in closure #1 in Attribute.init<A>(_:) + 24 (:-1)
339 AttributeGraph                	0x00000001d1644914 AG::ClosureFunctionGU<void, void*, unsigned int>::operator()(void*, unsigned int) const + 12 (:-1)
340 AttributeGraph                	0x00000001d1644914 AG::Graph::UpdateStack::update() + 496 (:-1)
341 AttributeGraph                	0x00000001d164674c AG::Subgraph::update(unsigned int) + 972 (:-1)
342 SwiftUICore                   	0x00000001a8229040 specialized GraphHost.runTransaction(_:do:id:) + 368 (:-1)
343 SwiftUICore                   	0x00000001a81c179c specialized GraphHost.runTransaction(_:do:id:) + 28 (:-1)
344 SwiftUICore                   	0x00000001a81c179c implicit closure #1 in GraphHost.flushTransactions() + 28 (:-1)
345 SwiftUICore                   	0x00000001a81c179c GraphHost.flushTransactions() + 180 (:-1)
346 SwiftUICore                   	0x00000001a81c0bd8 closure #2 in closure #1 in ViewGraphRootValueUpdater.render(interval:updateDisplayList:targetTimestamp:) + 52 (:-1)
347 SwiftUICore                   	0x00000001a81c0bd8 closure #1 in ViewGraphRootValueUpdater.render(interval:updateDisplayList:targetTimestamp:) + 880 (:-1)
348 SwiftUICore                   	0x00000001a81c0818 ViewGraphRootValueUpdater.render(interval:updateDisplayList:targetTimestamp:) + 584 (:-1)
349 UIKitCore                     	0x00000001a3e6a580 UIHostingViewBase.renderForPreferences(updateDisplayList:) + 204 (:-1)
350 UIKitCore                     	0x00000001a3e6a580 closure #1 in UIHostingViewBase._setNeedsUpdate() + 488 (:-1)
351 UIKitCore                     	0x00000001a3ac05c4 <deduplicated_symbol> + 36 (:-1)
352 libdispatch.dylib             	0x00000001d89669a8 _dispatch_call_block_and_release + 32 (:-1)
353 libdispatch.dylib             	0x00000001d89801e4 _dispatch_client_callout + 16 (:-1)
354 libdispatch.dylib             	0x00000001d899de10 _dispatch_continuation_invoke_inline + 208 (:-1)
355 libdispatch.dylib             	0x00000001d899de10 _dispatch_continuation_pop_inline + 476 (:-1)
356 libdispatch.dylib             	0x00000001d899de10 _dispatch_main_queue_drain.cold.6 + 832 (:-1)
357 libdispatch.dylib             	0x00000001d8975964 _os_tsd_set_direct + 16 (:-1)
358 libdispatch.dylib             	0x00000001d8975964 _pthread_setspecific_direct + 16 (:-1)
359 libdispatch.dylib             	0x00000001d8975964 _dispatch_thread_setspecific + 16 (:-1)
360 libdispatch.dylib             	0x00000001d8975964 _dispatch_adopt_wlh_anon_recurse + 72 (:-1)
361 libdispatch.dylib             	0x00000001d8975964 _dispatch_adopt_wlh_anon + 72 (:-1)
362 libdispatch.dylib             	0x00000001d8975964 _dispatch_main_queue_drain + 176 (:-1)
363 libdispatch.dylib             	0x00000001d89758a4 _dispatch_main_queue_callback_4CF + 44 (:-1)
364 CoreFoundation                	0x000000019dee1068 __CFRUNLOOP_IS_SERVICING_THE_MAIN_DISPATCH_QUEUE__ + 16 (:-1)
365 CoreFoundation                	0x000000019de6e604 __CFRunLoopRun + 1944 (:-1)
366 CoreFoundation                	0x000000019de6d54c _CFRunLoopRunSpecificWithOptions + 532 (:-1)
367 GraphicsServices              	0x0000000243a19498 GSEventRunModal + 120 (:-1)
368 UIKitCore                     	0x00000001a3ba1670 -[UIApplication _run] + 796 (:-1)
369 UIKitCore                     	0x00000001a3b0c158 UIApplicationMain + 332 (:-1)
370 SwiftUI                       	0x00000001a6efb570 closure #1 in KitRendererCommon(_:) + 168 (:-1)
371 SwiftUI                       	0x00000001a6ef80f4 specialized UnsafeMutablePointer<>.withMemoryRebound<A, B, C>(to:capacity:_:) + 12 (:-1)
372 SwiftUI                       	0x00000001a6ef80f4 KitRendererCommon(_:) + 16 (:-1)
373 SwiftUI                       	0x00000001a6ef80f4 runApp<A>(_:) + 112 (:-1)
374 SwiftUI                       	0x00000001a6ef7c48 static App.main() + 172 (:-1)
375 CatchWords                    	0x0000000102c13520 static CatchWordsApp.$main() + 52 (CatchWordsApp.swift:0)
376 CatchWords                    	0x0000000102c13520 main + 64
377 dyld                          	0x000000019aa79c1c start + 6928 (:-1)

Thread 1:
0   libsystem_kernel.dylib        	0x000000024d44a808 __semwait_signal + 8 (:-1)
1   libsystem_c.dylib             	0x00000001a99c882c nanosleep + 220 (:-1)
2   libsystem_c.dylib             	0x00000001a99c8954 sleep + 52 (:-1)
3   CatchWords                    	0x0000000102e6f114 monitorThreadCache + 220
4   libsystem_pthread.dylib       	0x00000001fd736438 _pthread_start + 136 (:-1)
5   libsystem_pthread.dylib       	0x00000001fd7328cc thread_start + 8 (:-1)

Thread 2 name:
Thread 2:
0   libsystem_kernel.dylib        	0x000000024d444cd4 mach_msg2_trap + 8 (:-1)
1   libsystem_kernel.dylib        	0x000000024d44830c mach_msg2_internal + 76 (:-1)
2   libsystem_kernel.dylib        	0x000000024d4462c0 mach_msg2 + 40 (:-1)
3   libsystem_kernel.dylib        	0x000000024d4462c0 mig_mach_msg + 44 (:-1)
4   libsystem_kernel.dylib        	0x000000024d4462c0 thread_suspend + 108 (:-1)
5   CatchWords                    	0x0000000102e58fb8 handleExceptions + 116
6   libsystem_pthread.dylib       	0x00000001fd736438 _pthread_start + 136 (:-1)
7   libsystem_pthread.dylib       	0x00000001fd7328cc thread_start + 8 (:-1)

Thread 3 name:
Thread 3:
0   libsystem_kernel.dylib        	0x000000024d444cd4 mach_msg2_trap + 8 (:-1)
1   libsystem_kernel.dylib        	0x000000024d44830c mach_msg2_internal + 76 (:-1)
2   libsystem_kernel.dylib        	0x000000024d44822c mach_msg2 + 4 (:-1)
3   libsystem_kernel.dylib        	0x000000024d44822c mach_msg_overwrite + 424 (:-1)
4   libsystem_kernel.dylib        	0x000000024d448078 mach_msg + 24 (:-1)
5   CatchWords                    	0x0000000102e58fe4 handleExceptions + 160
6   libsystem_pthread.dylib       	0x00000001fd736438 _pthread_start + 136 (:-1)
7   libsystem_pthread.dylib       	0x00000001fd7328cc thread_start + 8 (:-1)

Thread 4 name:
Thread 4:
0   libsystem_kernel.dylib        	0x000000024d44a808 __semwait_signal + 8 (:-1)
1   libsystem_c.dylib             	0x00000001a99c882c nanosleep + 220 (:-1)
2   Foundation                    	0x000000019b3e5508 +[NSThread sleepForTimeInterval:] + 152 (:-1)
3   CatchWords                    	0x0000000102f0ef60 SentryANRTrackerV2.detectANRs() + 824
4   CatchWords                    	0x00000001024d6a84 <deduplicated_symbol> + 36
5   Foundation                    	0x000000019bb02f2c __NSThread__block_start__ + 76 (:-1)
6   libsystem_pthread.dylib       	0x00000001fd736438 _pthread_start + 136 (:-1)
7   libsystem_pthread.dylib       	0x00000001fd7328cc thread_start + 8 (:-1)

Thread 5 name:
Thread 5:
0   libsystem_kernel.dylib        	0x000000024d444c50 semaphore_wait_trap + 8 (:-1)
1   caulk                         	0x00000002b7b08c6c caulk::mach::semaphore::wait_or_error() + 8 (:-1)
2   caulk                         	0x00000002b7b08c6c caulk::semaphore::timed_wait(double) + 224 (:-1)
3   caulk                         	0x00000002b7b08cb8 caulk::semaphore::wait() + 12 (:-1)
4   caulk                         	0x00000002b7b08cb8 caulk::concurrent::details::worker_thread::run() + 32 (:-1)
5   caulk                         	0x00000002b7b0cf54 std::__1::__invoke_result_impl<void, void (caulk::concurrent::details::worker_thread::*&)(), caulk::concurrent::details::worker_thread*&>::type std::__1::__invoke[abi:nqe210106]<void (caulk::concur... + 72 (:-1)
6   caulk                         	0x00000002b7b0cf54 decltype(auto) std::__1::__apply_tuple_impl[abi:nqe210106]<void (caulk::concurrent::details::worker_thread::*&)(), std::__1::tuple<caulk::concurrent::details::worker_thread*>&, 0ul>(void (caulk::co... + 72 (:-1)
7   caulk                         	0x00000002b7b0cf54 decltype(auto) std::__1::apply[abi:nqe210106]<void (caulk::concurrent::details::worker_thread::*&)(), std::__1::tuple<caulk::concurrent::details::worker_thread*>&>(void (caulk::concurrent::details:... + 72 (:-1)
8   caulk                         	0x00000002b7b0cf54 void* caulk::thread_proxy<std::__1::tuple<caulk::thread::attributes, void (caulk::concurrent::details::worker_thread::*)(), std::__1::tuple<caulk::concurrent::details::worker_thread*>>>(void*) + 96 (:-1)
9   libsystem_pthread.dylib       	0x00000001fd736438 _pthread_start + 136 (:-1)
10  libsystem_pthread.dylib       	0x00000001fd7328cc thread_start + 8 (:-1)

Thread 6 name:
Thread 6:
0   libsystem_kernel.dylib        	0x000000024d444c50 semaphore_wait_trap + 8 (:-1)
1   caulk                         	0x00000002b7b08c6c caulk::mach::semaphore::wait_or_error() + 8 (:-1)
2   caulk                         	0x00000002b7b08c6c caulk::semaphore::timed_wait(double) + 224 (:-1)
3   caulk                         	0x00000002b7b08cb8 caulk::semaphore::wait() + 12 (:-1)
4   caulk                         	0x00000002b7b08cb8 caulk::concurrent::details::worker_thread::run() + 32 (:-1)
5   caulk                         	0x00000002b7b0cf54 std::__1::__invoke_result_impl<void, void (caulk::concurrent::details::worker_thread::*&)(), caulk::concurrent::details::worker_thread*&>::type std::__1::__invoke[abi:nqe210106]<void (caulk::concur... + 72 (:-1)
6   caulk                         	0x00000002b7b0cf54 decltype(auto) std::__1::__apply_tuple_impl[abi:nqe210106]<void (caulk::concurrent::details::worker_thread::*&)(), std::__1::tuple<caulk::concurrent::details::worker_thread*>&, 0ul>(void (caulk::co... + 72 (:-1)
7   caulk                         	0x00000002b7b0cf54 decltype(auto) std::__1::apply[abi:nqe210106]<void (caulk::concurrent::details::worker_thread::*&)(), std::__1::tuple<caulk::concurrent::details::worker_thread*>&>(void (caulk::concurrent::details:... + 72 (:-1)
8   caulk                         	0x00000002b7b0cf54 void* caulk::thread_proxy<std::__1::tuple<caulk::thread::attributes, void (caulk::concurrent::details::worker_thread::*)(), std::__1::tuple<caulk::concurrent::details::worker_thread*>>>(void*) + 96 (:-1)
9   libsystem_pthread.dylib       	0x00000001fd736438 _pthread_start + 136 (:-1)
10  libsystem_pthread.dylib       	0x00000001fd7328cc thread_start + 8 (:-1)

Thread 7 name:
Thread 7:
0   libsystem_kernel.dylib        	0x000000024d444cd4 mach_msg2_trap + 8 (:-1)
1   libsystem_kernel.dylib        	0x000000024d44830c mach_msg2_internal + 76 (:-1)
2   libsystem_kernel.dylib        	0x000000024d44822c mach_msg2 + 4 (:-1)
3   libsystem_kernel.dylib        	0x000000024d44822c mach_msg_overwrite + 424 (:-1)
4   libsystem_kernel.dylib        	0x000000024d448078 mach_msg + 24 (:-1)
5   CoreFoundation                	0x000000019dea4374 __CFRunLoopServiceMachPort + 160 (:-1)
6   CoreFoundation                	0x000000019de6e310 __CFRunLoopRun + 1188 (:-1)
7   CoreFoundation                	0x000000019de6d54c _CFRunLoopRunSpecificWithOptions + 532 (:-1)
8   Foundation                    	0x000000019b0dacf0 -[NSRunLoop(NSRunLoop) runMode:beforeDate:] + 212 (:-1)
9   Foundation                    	0x000000019b0dabd8 -[NSRunLoop(NSRunLoop) runUntilDate:] + 64 (:-1)
10  UIKitCore                     	0x00000001a3b66eac -[UIEventFetcher threadMain] + 420 (:-1)
11  Foundation                    	0x000000019b15e914 __NSThread__start__ + 732 (:-1)
12  libsystem_pthread.dylib       	0x00000001fd736438 _pthread_start + 136 (:-1)
13  libsystem_pthread.dylib       	0x00000001fd7328cc thread_start + 8 (:-1)

Thread 8 name:
Thread 8:
0   libsystem_kernel.dylib        	0x000000024d444cd4 mach_msg2_trap + 8 (:-1)
1   libsystem_kernel.dylib        	0x000000024d44830c mach_msg2_internal + 76 (:-1)
2   libsystem_kernel.dylib        	0x000000024d44822c mach_msg2 + 4 (:-1)
3   libsystem_kernel.dylib        	0x000000024d44822c mach_msg_overwrite + 424 (:-1)
4   libsystem_kernel.dylib        	0x000000024d448078 mach_msg + 24 (:-1)
5   CoreFoundation                	0x000000019dea4374 __CFRunLoopServiceMachPort + 160 (:-1)
6   CoreFoundation                	0x000000019de6e310 __CFRunLoopRun + 1188 (:-1)
7   CoreFoundation                	0x000000019de6d54c _CFRunLoopRunSpecificWithOptions + 532 (:-1)
8   CFNetwork                     	0x00000001b337db54 -[__CFN_CoreSchedulingSetRunnable runForever] + 24 (:-1)
9   CFNetwork                     	0x00000001b337db54 +[__CFN_CoreSchedulingSetRunnable _run:] + 416 (:-1)
10  Foundation                    	0x000000019b15e914 __NSThread__start__ + 732 (:-1)
11  libsystem_pthread.dylib       	0x00000001fd736438 _pthread_start + 136 (:-1)
12  libsystem_pthread.dylib       	0x00000001fd7328cc thread_start + 8 (:-1)

Thread 9 name:
Thread 9:
0   libsystem_kernel.dylib        	0x000000024d444c50 semaphore_wait_trap + 8 (:-1)
1   caulk                         	0x00000002b7b08c6c caulk::mach::semaphore::wait_or_error() + 8 (:-1)
2   caulk                         	0x00000002b7b08c6c caulk::semaphore::timed_wait(double) + 224 (:-1)
3   caulk                         	0x00000002b7b08cb8 caulk::semaphore::wait() + 12 (:-1)
4   caulk                         	0x00000002b7b08cb8 caulk::concurrent::details::worker_thread::run() + 32 (:-1)
5   caulk                         	0x00000002b7b0cf54 std::__1::__invoke_result_impl<void, void (caulk::concurrent::details::worker_thread::*&)(), caulk::concurrent::details::worker_thread*&>::type std::__1::__invoke[abi:nqe210106]<void (caulk::concur... + 72 (:-1)
6   caulk                         	0x00000002b7b0cf54 decltype(auto) std::__1::__apply_tuple_impl[abi:nqe210106]<void (caulk::concurrent::details::worker_thread::*&)(), std::__1::tuple<caulk::concurrent::details::worker_thread*>&, 0ul>(void (caulk::co... + 72 (:-1)
7   caulk                         	0x00000002b7b0cf54 decltype(auto) std::__1::apply[abi:nqe210106]<void (caulk::concurrent::details::worker_thread::*&)(), std::__1::tuple<caulk::concurrent::details::worker_thread*>&>(void (caulk::concurrent::details:... + 72 (:-1)
8   caulk                         	0x00000002b7b0cf54 void* caulk::thread_proxy<std::__1::tuple<caulk::thread::attributes, void (caulk::concurrent::details::worker_thread::*)(), std::__1::tuple<caulk::concurrent::details::worker_thread*>>>(void*) + 96 (:-1)
9   libsystem_pthread.dylib       	0x00000001fd736438 _pthread_start + 136 (:-1)
10  libsystem_pthread.dylib       	0x00000001fd7328cc thread_start + 8 (:-1)

Thread 10 name:
Thread 10:
0   libsystem_kernel.dylib        	0x000000024d444c50 semaphore_wait_trap + 8 (:-1)
1   libdispatch.dylib             	0x00000001d8968410 _dispatch_sema4_wait + 28 (:-1)
2   libdispatch.dylib             	0x00000001d8968aa0 _dispatch_semaphore_wait_slow + 132 (:-1)
3   UIKitCore                     	0x00000001a3e5a1f8 0x1a3a80000 + 4039160
4   UIKitCore                     	0x00000001a3e5a1b0 closure #2 in InProcessAnimationManager.startAdvancing(_:) + 308 (:-1)
5   UIKitCore                     	0x00000001a3ac05c4 <deduplicated_symbol> + 36 (:-1)
6   Foundation                    	0x000000019b15e914 __NSThread__start__ + 732 (:-1)
7   libsystem_pthread.dylib       	0x00000001fd736438 _pthread_start + 136 (:-1)
8   libsystem_pthread.dylib       	0x00000001fd7328cc thread_start + 8 (:-1)

Thread 11 name:
Thread 11:
0   libsystem_kernel.dylib        	0x000000024d444cd4 mach_msg2_trap + 8 (:-1)
1   libsystem_kernel.dylib        	0x000000024d44830c mach_msg2_internal + 76 (:-1)
2   libsystem_kernel.dylib        	0x000000024d44822c mach_msg2 + 4 (:-1)
3   libsystem_kernel.dylib        	0x000000024d44822c mach_msg_overwrite + 424 (:-1)
4   libsystem_kernel.dylib        	0x000000024d448078 mach_msg + 24 (:-1)
5   CoreFoundation                	0x000000019dea4374 __CFRunLoopServiceMachPort + 160 (:-1)
6   CoreFoundation                	0x000000019de6e310 __CFRunLoopRun + 1188 (:-1)
7   CoreFoundation                	0x000000019de6d54c _CFRunLoopRunSpecificWithOptions + 532 (:-1)
8   CoreFoundation                	0x000000019df1dde4 CFRunLoopRun + 64 (:-1)
9   ANEServices                   	0x00000001dda698f0 ANE::ANEServicesThreadStart(ANE::ANEServicesThreadParams*) + 152 (:-1)
10  libsystem_pthread.dylib       	0x00000001fd736438 _pthread_start + 136 (:-1)
11  libsystem_pthread.dylib       	0x00000001fd7328cc thread_start + 8 (:-1)

Thread 12 name:
Thread 12:
0   libsystem_kernel.dylib        	0x000000024d444cd4 mach_msg2_trap + 8 (:-1)
1   libsystem_kernel.dylib        	0x000000024d44830c mach_msg2_internal + 76 (:-1)
2   libsystem_kernel.dylib        	0x000000024d44822c mach_msg2 + 4 (:-1)
3   libsystem_kernel.dylib        	0x000000024d44822c mach_msg_overwrite + 424 (:-1)
4   libsystem_kernel.dylib        	0x000000024d448078 mach_msg + 24 (:-1)
5   CoreFoundation                	0x000000019dea4374 __CFRunLoopServiceMachPort + 160 (:-1)
6   CoreFoundation                	0x000000019de6e310 __CFRunLoopRun + 1188 (:-1)
7   CoreFoundation                	0x000000019de6d54c _CFRunLoopRunSpecificWithOptions + 532 (:-1)
8   CoreFoundation                	0x000000019df1dde4 CFRunLoopRun + 64 (:-1)
9   ANEServices                   	0x00000001dda698f0 ANE::ANEServicesThreadStart(ANE::ANEServicesThreadParams*) + 152 (:-1)
10  libsystem_pthread.dylib       	0x00000001fd736438 _pthread_start + 136 (:-1)
11  libsystem_pthread.dylib       	0x00000001fd7328cc thread_start + 8 (:-1)

Thread 13 name:
Thread 13:
0   libsystem_kernel.dylib        	0x000000024d444cd4 mach_msg2_trap + 8 (:-1)
1   libsystem_kernel.dylib        	0x000000024d44830c mach_msg2_internal + 76 (:-1)
2   libsystem_kernel.dylib        	0x000000024d44822c mach_msg2 + 4 (:-1)
3   libsystem_kernel.dylib        	0x000000024d44822c mach_msg_overwrite + 424 (:-1)
4   libsystem_kernel.dylib        	0x000000024d448078 mach_msg + 24 (:-1)
5   CoreFoundation                	0x000000019dea4374 __CFRunLoopServiceMachPort + 160 (:-1)
6   CoreFoundation                	0x000000019de6e310 __CFRunLoopRun + 1188 (:-1)
7   CoreFoundation                	0x000000019de6d54c _CFRunLoopRunSpecificWithOptions + 532 (:-1)
8   CoreFoundation                	0x000000019df1dde4 CFRunLoopRun + 64 (:-1)
9   ANEServices                   	0x00000001dda698f0 ANE::ANEServicesThreadStart(ANE::ANEServicesThreadParams*) + 152 (:-1)
10  libsystem_pthread.dylib       	0x00000001fd736438 _pthread_start + 136 (:-1)
11  libsystem_pthread.dylib       	0x00000001fd7328cc thread_start + 8 (:-1)

Thread 14 name:
Thread 14:
0   libsystem_kernel.dylib        	0x000000024d444cd4 mach_msg2_trap + 8 (:-1)
1   libsystem_kernel.dylib        	0x000000024d44830c mach_msg2_internal + 76 (:-1)
2   libsystem_kernel.dylib        	0x000000024d44822c mach_msg2 + 4 (:-1)
3   libsystem_kernel.dylib        	0x000000024d44822c mach_msg_overwrite + 424 (:-1)
4   libsystem_kernel.dylib        	0x000000024d448078 mach_msg + 24 (:-1)
5   CoreFoundation                	0x000000019dea4374 __CFRunLoopServiceMachPort + 160 (:-1)
6   CoreFoundation                	0x000000019de6e310 __CFRunLoopRun + 1188 (:-1)
7   CoreFoundation                	0x000000019de6d54c _CFRunLoopRunSpecificWithOptions + 532 (:-1)
8   CoreFoundation                	0x000000019df1dde4 CFRunLoopRun + 64 (:-1)
9   ANEServices                   	0x00000001dda698f0 ANE::ANEServicesThreadStart(ANE::ANEServicesThreadParams*) + 152 (:-1)
10  libsystem_pthread.dylib       	0x00000001fd736438 _pthread_start + 136 (:-1)
11  libsystem_pthread.dylib       	0x00000001fd7328cc thread_start + 8 (:-1)

Thread 15:

Thread 16:

Thread 17:

Thread 18:

Thread 19:

Thread 20:

Thread 21:

Thread 22:

Thread 23 name:
Thread 23 Crashed:
0   libsystem_kernel.dylib        	0x000000024d44f1d0 __pthread_kill + 8 (:-1)
1   libsystem_pthread.dylib       	0x00000001fd7397dc pthread_kill + 268 (:-1)
2   libsystem_c.dylib             	0x00000001a9a32fcc abort + 148 (:-1)
3   libc++abi.dylib               	0x000000019ab22fd4 __abort_message + 132 (:-1)
4   libc++abi.dylib               	0x000000019ab24b90 demangling_terminate_handler() + 296 (:-1)
5   libobjc.A.dylib               	0x000000019aa23868 _objc_terminate() + 156 (:-1)
6   CatchWords                    	0x0000000102e57b2c CPPExceptionTerminate() + 428
7   libc++abi.dylib               	0x000000019ab2f1f8 std::__terminate(void (*)()) + 16 (:-1)
8   libc++abi.dylib               	0x000000019ab30e18 __cxxabiv1::failed_throw(__cxxabiv1::__cxa_exception*) + 88 (:-1)
9   libc++abi.dylib               	0x000000019ab1d360 __cxa_throw + 92 (:-1)
10  libobjc.A.dylib               	0x000000019aa2138c objc_exception_throw + 448 (:-1)
11  Foundation                    	0x000000019ba85520 -[NSAssertionHandler handleFailureInMethod:object:file:lineNumber:description:] + 288 (:-1)
12  UIKitCore                     	0x00000001a507c7ec -[UIApplication _performBlockAfterCATransactionCommitSynchronizes:] + 280 (:-1)
13  UIKitCore                     	0x00000001a5089ee8 -[UIApplication _updateStateRestorationArchiveForBackgroundEvent:saveState:exitIfCouldNotRestoreState:updateSnapshot:windowScene:] + 528 (:-1)
14  UIKitCore                     	0x00000001a508a29c -[UIApplication _updateSnapshotAndStateRestorationWithAction:windowScene:] + 144 (:-1)
15  CatchWords                    	0x000000010259a278 @objc closure #1 in NotificationRouter.userNotificationCenter(_:didReceive:) + 76 (/<compiler-generated>:0)
16  CatchWords                    	0x0000000102440859 <deduplicated_symbol> + 1
17  CatchWords                    	0x00000001024cd661 <deduplicated_symbol> + 1
18  CatchWords                    	0x0000000102440859 <deduplicated_symbol> + 1
19  CatchWords                    	0x00000001024cd661 <deduplicated_symbol> + 1
20  CatchWords                    	0x00000001024caae9 <deduplicated_symbol> + 1
21  CatchWords                    	0x00000001024cd661 <deduplicated_symbol> + 1
22  libswift_Concurrency.dylib    	0x000000019bf5f385 completeTaskWithClosure(swift::AsyncContext*, swift::SwiftError*) + 1 (:-1)

Thread 24:

Thread 25:

Thread 26:

Thread 27:

Thread 28:

Thread 29:

Thread 30:

Thread 31:

Thread 32:

Thread 33:

Thread 34 name:
Thread 34 name:
Thread 34:
0   libsystem_kernel.dylib        	0x000000024d444cd4 mach_msg2_trap + 8 (:-1)
1   libsystem_kernel.dylib        	0x000000024d44830c mach_msg2_internal + 76 (:-1)
2   libsystem_kernel.dylib        	0x000000024d44822c mach_msg2 + 4 (:-1)
3   libsystem_kernel.dylib        	0x000000024d44822c mach_msg_overwrite + 424 (:-1)
4   libsystem_kernel.dylib        	0x000000024d448078 mach_msg + 24 (:-1)
5   libdispatch.dylib             	0x00000001d8981984 _dispatch_mach_msg_reply_recv + 204 (:-1)
6   libdispatch.dylib             	0x00000001d8981984 _dispatch_mach_send_and_wait_for_reply + 548 (:-1)
7   libdispatch.dylib             	0x00000001d8981d24 dispatch_mach_send_with_result_and_wait_for_reply + 60 (:-1)
8   libxpc.dylib                  	0x00000001b28e3edc _xpc_connection_enqueue_sync + 88 (:-1)
9   libxpc.dylib                  	0x00000001b28e3edc xpc_connection_send_message_with_reply_sync + 256 (:-1)
10  Foundation                    	0x000000019b111734 __NSXPCCONNECTION_IS_WAITING_FOR_A_SYNCHRONOUS_REPLY__ + 16 (:-1)
11  Foundation                    	0x000000019b0f906c -[NSXPCConnection _sendInvocation:orArguments:count:methodSignature:selector:withProxy:] + 2100 (:-1)
12  CoreFoundation                	0x000000019dea23cc ___forwarding___ + 1072 (:-1)
13  CoreFoundation                	0x000000019deace90 _CF_forwarding_prep_0 + 96 (:-1)
14  AudioSession                  	0x00000001c923db40 avas::client::SessionCore::GetCachedProperty(NSString*) const + 156 (:-1)
15  AudioSession                  	0x00000001c923d8ac avas::client::CacheManager::refreshCachedProperty(AVAudioSession*, NSString*) + 124 (:-1)
16  AudioSession                  	0x00000001c9239d6c avas::client::CacheManager::checkAndRefreshCacheForNotification(AVAudioSession*, NSString*) + 260 (:-1)
17  AudioSession                  	0x00000001c92384e4 avas::client::SessionCoreLegacy_iOS::HandleDeferredMessage(NSString*, NSDictionary*) + 156 (:-1)
18  AudioSession                  	0x00000001c9237818 avas::client::SessionCore::HandlePing() + 828 (:-1)
19  AudioSession                  	0x00000001c923749c invocation function for block in avas::client::SessionCore::DispatchPing() + 52 (:-1)
20  libdispatch.dylib             	0x00000001d89669a8 _dispatch_call_block_and_release + 32 (:-1)
21  libdispatch.dylib             	0x00000001d89801e4 _dispatch_client_callout + 16 (:-1)
22  libdispatch.dylib             	0x00000001d896efb0 _dispatch_continuation_invoke_inline + 136 (:-1)
23  libdispatch.dylib             	0x00000001d896efb0 _dispatch_continuation_pop_inline + 136 (:-1)
24  libdispatch.dylib             	0x00000001d896efb0 _dispatch_lane_drain + 700 (:-1)
25  libdispatch.dylib             	0x00000001d896efb0 _dispatch_lane_serial_drain + 740 (:-1)
26  libdispatch.dylib             	0x00000001d896fae4 _dispatch_lane_invoke2 + 52 (:-1)
27  libdispatch.dylib             	0x00000001d896fae4 _dispatch_queue_class_invoke + 400 (:-1)
28  libdispatch.dylib             	0x00000001d896fae4 _dispatch_lane_invoke + 448 (:-1)
29  libdispatch.dylib             	0x00000001d8978900 _dispatch_continuation_pop_inline + 148 (:-1)
30  libdispatch.dylib             	0x00000001d8978900 _dispatch_root_queue_drain + 360 (:-1)
31  libdispatch.dylib             	0x00000001d89786c4 _dispatch_worker_thread + 268 (:-1)
32  libsystem_pthread.dylib       	0x00000001fd736438 _pthread_start + 136 (:-1)
33  libsystem_pthread.dylib       	0x00000001fd7328cc thread_start + 8 (:-1)


Thread 23 crashed with ARM Thread State (64-bit):
    x0: 0x0000000000000000   x1: 0x0000000000000000   x2: 0x0000000000000000   x3: 0x0000000000000000
    x4: 0x000000019ab31cd3   x5: 0x000000016e5611b0   x6: 0x000000000000006e   x7: 0xfffff0003ffff800
    x8: 0x6ac34fdaaddc454e   x9: 0x6ac34fdbc38a754e  x10: 0x0000000000000002  x11: 0x00000000fffffffd
   x12: 0x0000000000000000  x13: 0x0000000000000000  x14: 0x0000000000000000  x15: 0x0000000000000000
   x16: 0x0000000000000148  x17: 0x000000016e563000  x18: 0x0000000000000000  x19: 0x0000000000000006
   x20: 0x0000000000022183  x21: 0x000000016e5630e0  x22: 0x00000002044ac000  x23: 0x0000000000000001
   x24: 0x0000000103ffd170  x25: 0x0000000000000000  x26: 0x00000002075638f0  x27: 0x0000000207563908
   x28: 0x0000000000000000   fp: 0x000000016e561120   lr: 0x00000001fd7397dc
    sp: 0x000000016e561100   pc: 0x000000024d44f1d0 cpsr: 0x40000000
   esr: 0x56000080 (Syscall)


Binary Images:
        0x102414000 -         0x1033e3fff CatchWords arm64  <f7801e3877613e2ab0db0417468efec9> /private/var/containers/Bundle/Application/37DCD888-40C0-446B-AC01-3503A4B071A6/CatchWords.app/CatchWords
        0x1037c8000 -         0x1037d3fff libobjc-trampolines.dylib arm64e  <004ce93cf1423d68b3c330c6efef4d65> /private/preboot/Cryptexes/OS/usr/lib/libobjc-trampolines.dylib
        0x19a9f0000 -         0x19aa4147f libobjc.A.dylib arm64e  <794fd2568a8d3c8d91aaaac27ef3512c> /usr/lib/libobjc.A.dylib
        0x19aa75000 -         0x19ab1a47f dyld arm64e  <0f8d35b6556f3e348eaa80ab54047dc5> /usr/lib/dyld
        0x19ab1b000 -         0x19ab3559f libc++abi.dylib arm64e  <4e297677d0143f999183690b92b47fc3> /usr/lib/libc++abi.dylib
        0x19ab36000 -         0x19b0cf8bf libswiftCore.dylib arm64e  <1539faa731da3c41b14aa9691063824d> /usr/lib/swift/libswiftCore.dylib
        0x19b0d0000 -         0x19bf59cbf Foundation arm64e  <73841aa3bfdd322d8dc2e5185a14dee1> /System/Library/Frameworks/Foundation.framework/Foundation
        0x19bf5a000 -         0x19bfe4925 libswift_Concurrency.dylib arm64e  <ff77abd1158438808851c0f3ad15f77d> /usr/lib/swift/libswift_Concurrency.dylib
        0x19de3f000 -         0x19e3dba3f CoreFoundation arm64e  <101eb2f1191534a08bc9631d03753b84> /System/Library/Frameworks/CoreFoundation.framework/CoreFoundation
        0x1a3a80000 -         0x1a5fc363f UIKitCore arm64e  <0d94422ffe7c302eb8963bc5873c0cfc> /System/Library/PrivateFrameworks/UIKitCore.framework/UIKitCore
        0x1a6ecb000 -         0x1a815699f SwiftUI arm64e  <17adc54e93ab3f13b469e3f53181fc4d> /System/Library/Frameworks/SwiftUI.framework/SwiftUI
        0x1a81a4000 -         0x1a90a07bf SwiftUICore arm64e  <82a21ce44e4338fb9862f0be7b909df1> /System/Library/Frameworks/SwiftUICore.framework/SwiftUICore
        0x1a99bc000 -         0x1a9a3b5ff libsystem_c.dylib arm64e  <ff42982180de3a6899cb0b2e707e8d48> /usr/lib/system/libsystem_c.dylib
        0x1b28d2000 -         0x1b292365f libxpc.dylib arm64e  <72214f26ea8c3f8abdf72f518fe9f87e> /usr/lib/system/libxpc.dylib
        0x1b32ec000 -         0x1b369c77f CFNetwork arm64e  <3ae849fe8a7d388c86ef64dedb9fc5c6> /System/Library/Frameworks/CFNetwork.framework/CFNetwork
        0x1c9232000 -         0x1c929de3f AudioSession arm64e  <cffc0746f53f3c7a9c5aadd7008d6f6f> /System/Library/PrivateFrameworks/AudioSession.framework/AudioSession
        0x1d1638000 -         0x1d167d19f AttributeGraph arm64e  <a973ad423cff3c90bc78e4e0bffa155b> /System/Library/PrivateFrameworks/AttributeGraph.framework/AttributeGraph
        0x1d8965000 -         0x1d89ab5ff libdispatch.dylib arm64e  <49c0cd3ea6963b11ba925755f0c3c6e3> /usr/lib/system/libdispatch.dylib
        0x1dda46000 -         0x1dda7689f ANEServices arm64e  <a1b9a671516030629696e471e4b7e6ca> /System/Library/PrivateFrameworks/ANEServices.framework/ANEServices
        0x1fd732000 -         0x1fd73e4ef libsystem_pthread.dylib arm64e  <34b44744bc64386eab90eee86b23ac46> /usr/lib/system/libsystem_pthread.dylib
        0x243a18000 -         0x243a207bf GraphicsServices arm64e  <411165e2ee8e380eb2549977273971e3> /System/Library/PrivateFrameworks/GraphicsServices.framework/GraphicsServices
        0x24d444000 -         0x24d47fb1f libsystem_kernel.dylib arm64e  <18665b3f6d5133abb9e963062200ec42> /usr/lib/system/libsystem_kernel.dylib
        0x2b7b05000 -         0x2b7b2e01f caulk arm64e  <5dd354fba86f37328f36a88736414f79> /System/Library/PrivateFrameworks/caulk.framework/caulk

EOF
```

## 2. 2026-11-08T13:07:48.254Z  ビルド 1.0.5 (1089)
- deviceModel: iPad16_3
- deviceFamily: IPAD
- osVersion: 26.6.1
- appPlatform: IOS
- architecture: arm64e
- locale: ja-TW
- diskBytesAvailable: 155862286336
- batteryPercentage: 65
- screenWidthInPoints: 1210
- screenHeightInPoints: 834
- buildBundleId: com.nori.catchwords
- comment: （37 文字。公開しない）

```
Incident Identifier: D8E85A0A-6848-4A31-99AC-60535CF3B3DD
Distributor ID:      com.apple.TestFlight
Hardware Model:      iPad16,3
Process:             CatchWords [30246]
Path:                /private/var/containers/Bundle/Application/0FD6307B-76F0-4752-81A7-87E06B1D8AF2/CatchWords.app/CatchWords
Identifier:          com.nori.catchwords
Version:             1.0.5 (1089)
AppStoreTools:       27B52
AppVariant:          1:iPad16,3-A:26
Beta:                YES
Code Type:           ARM-64 (Native)
Role:                Foreground
Parent Process:      launchd [1]
Coalition:           com.nori.catchwords [741]

Date/Time:           2026-11-08 21:07:14.4415 +0800
Launch Time:         2026-11-08 19:46:48.4264 +0800
OS Version:          iPhone OS 26.6.1 (23G83)
Release Type:        User
Report Version:      104

Exception Type:  EXC_BREAKPOINT (SIGTRAP)
Exception Codes: 0x0000000000000001, 0x000000019ad3c878
Termination Reason: SIGNAL 5 Trace/BPT trap: 5
Terminating Process: exc handler [30246]

Triggered by Thread:  0


Thread 0 name:
Thread 0 Crashed:
0   libswiftCore.dylib            	0x000000019ad3c878 _assertionFailure(_:_:file:line:flags:) + 168 (:-1)
1   SwiftUICore                   	0x00000001a827f3b4 specialized EnvironmentValues.subscript.getter + 312 (:-1)
2   SwiftUICore                   	0x00000001a827f1b8 Environment.init<A>(_:) + 64 (:-1)
3   libswiftCore.dylib            	0x000000019ab89e34 specialized RawKeyPathComponent._projectReadOnly<A, B, C>(_:to:endingWith:_:pointer:) + 184 (:-1)
4   libswiftCore.dylib            	0x000000019ab89e34 specialized closure #1 in closure #2 in KeyPath._projectReadOnly(from:) + 184 (:-1)
5   libswiftCore.dylib            	0x000000019ab89e34 specialized closure #2 in KeyPath._projectReadOnly(from:) + 236 (:-1)
6   libswiftCore.dylib            	0x000000019ab89e34 specialized AnyKeyPath.withBuffer<A>(_:) + 244 (:-1)
7   libswiftCore.dylib            	0x000000019ab89e34 KeyPath._projectReadOnly(from:) + 624 (:-1)
8   libswiftCore.dylib            	0x000000019ab89bb8 swift_getAtKeyPath + 24 (:-1)
9   SwiftUICore                   	0x00000001a81f4158 closure #1 in EnvironmentBox.update(property:phase:) + 72 (:-1)
10  SwiftUICore                   	0x00000001a81f4108 partial apply for closure #1 in EnvironmentBox.update(property:phase:) + 20 (:-1)
11  SwiftUICore                   	0x00000001a82015b0 closure #1 in ObservationCenter._withObservation<A>(do:) + 48 (:-1)
12  SwiftUICore                   	0x00000001a8201d64 partial apply for closure #1 in ObservationCenter._withObservation<A>(do:) + 28 (:-1)
13  SwiftUICore                   	0x00000001a81b0730 withUnsafeMutablePointer<A, B, C>(to:_:) + 160 (:-1)
14  SwiftUICore                   	0x00000001a81f3b78 specialized ObservationCenter._withObservation<A>(do:) + 196 (:-1)
15  SwiftUICore                   	0x00000001a81f3b78 specialized ObservationCenter._withObservationStashed<A>(do:) + 196 (:-1)
16  SwiftUICore                   	0x00000001a81f3b78 EnvironmentBox.update(property:phase:) + 1848 (:-1)
17  SwiftUICore                   	0x00000001a81c8ef4 static BoxVTable.update(elt:property:phase:) + 384 (:-1)
18  SwiftUICore                   	0x00000001a81c91c4 _DynamicPropertyBuffer.update(container:phase:) + 144 (:-1)
19  SwiftUICore                   	0x00000001a81c8d20 closure #1 in closure #1 in DynamicBody.updateValue() + 304 (:-1)
20  SwiftUICore                   	0x00000001a81c8d6c partial apply for closure #1 in closure #1 in DynamicBody.updateValue() + 32 (:-1)
21  SwiftUICore                   	0x00000001a81b0730 withUnsafeMutablePointer<A, B, C>(to:_:) + 160 (:-1)
22  SwiftUICore                   	0x00000001a81c8810 closure #1 in DynamicBody.updateValue() + 476 (:-1)
23  SwiftUICore                   	0x00000001a81c8224 specialized closure #1 in ObservationCenter._withObservation<A>(do:) + 56 (:-1)
24  SwiftUICore                   	0x00000001a81c8224 specialized closure #1 in ObservationCenter._withObservation<A>(do:) + 56 (:-1)
25  SwiftUICore                   	0x00000001a81c8224 specialized withUnsafeMutablePointer<A, B, C>(to:_:) + 56 (:-1)
26  SwiftUICore                   	0x00000001a81c8224 specialized ObservationCenter._withObservation<A>(do:) + 96 (:-1)
27  SwiftUICore                   	0x00000001a81c8224 specialized ObservationCenter._withObservationStashed<A>(do:) + 96 (:-1)
28  SwiftUICore                   	0x00000001a81c8224 specialized ObservationCenter._withObservation<A, B>(attribute:do:) + 140 (:-1)
29  SwiftUICore                   	0x00000001a81c8224 specialized StatefulRule.withObservation<A>(observationCenter:do:) + 172 (:-1)
30  SwiftUICore                   	0x00000001a81c8224 DynamicBody.updateValue() + 1220 (:-1)
31  SwiftUICore                   	0x00000001a86a3fd0 specialized implicit closure #1 in closure #1 in closure #1 in Attribute.init<A>(_:) + 12 (:-1)
32  SwiftUICore                   	0x00000001a86a3fd0 implicit closure #1 in closure #1 in closure #1 in Attribute.init<A>(_:) + 12 (:-1)
33  SwiftUICore                   	0x00000001a86a3fd0 partial apply for implicit closure #1 in closure #1 in closure #1 in Attribute.init<A>(_:) + 32 (:-1)
34  AttributeGraph                	0x00000001d1644914 AG::ClosureFunctionGU<void, void*, unsigned int>::operator()(void*, unsigned int) const + 12 (:-1)
35  AttributeGraph                	0x00000001d1644914 AG::Graph::UpdateStack::update() + 496 (:-1)
36  AttributeGraph                	0x00000001d164452c AG::Graph::update_attribute(AG::data::ptr<AG::Node>, unsigned int) + 352 (:-1)
37  AttributeGraph                	0x00000001d1643e68 AG::Graph::input_value_ref_slow(AG::data::ptr<AG::Node>, AG::AttributeID, unsigned int, unsigned int, AGSwiftMetadata const*, unsigned char&, long) + 680 (:-1)
38  AttributeGraph                	0x00000001d163e2a8 AG::Graph::input_value_ref(AG::data::ptr<AG::Node>, AG::AttributeID, unsigned int, unsigned int, AGSwiftMetadata const*, unsigned char&) + 128 (:-1)
39  AttributeGraph                	0x00000001d163e2a8 AGGraphGetValue + 232 (:-1)
40  SwiftUICore                   	0x00000001a81c70a8 specialized Attribute.wrappedValue.unsafeAddressor + 52 (:-1)
41  SwiftUICore                   	0x00000001a81c70a8 StaticBody.container.getter + 84 (:-1)
42  SwiftUICore                   	0x00000001a81c6fb0 closure #1 in StaticBody.updateValue() + 436 (:-1)
43  SwiftUICore                   	0x00000001a81c6774 specialized closure #1 in ObservationCenter._withObservation<A>(do:) + 36 (:-1)
44  SwiftUICore                   	0x00000001a81c6774 specialized closure #1 in ObservationCenter._withObservation<A>(do:) + 36 (:-1)
45  SwiftUICore                   	0x00000001a81c6774 specialized withUnsafeMutablePointer<A, B, C>(to:_:) + 36 (:-1)
46  SwiftUICore                   	0x00000001a81c6774 specialized ObservationCenter._withObservation<A>(do:) + 72 (:-1)
47  SwiftUICore                   	0x00000001a81c6774 specialized ObservationCenter._withObservationStashed<A>(do:) + 72 (:-1)
48  SwiftUICore                   	0x00000001a81c6774 specialized ObservationCenter._withObservation<A, B>(attribute:do:) + 112 (:-1)
49  SwiftUICore                   	0x00000001a81c6774 specialized StatefulRule.withObservation<A>(observationCenter:do:) + 140 (:-1)
50  SwiftUICore                   	0x00000001a81c6774 StaticBody.updateValue() + 836 (:-1)
51  SwiftUICore                   	0x00000001a86a3fd0 specialized implicit closure #1 in closure #1 in closure #1 in Attribute.init<A>(_:) + 12 (:-1)
52  SwiftUICore                   	0x00000001a86a3fd0 implicit closure #1 in closure #1 in closure #1 in Attribute.init<A>(_:) + 12 (:-1)
53  SwiftUICore                   	0x00000001a86a3fd0 partial apply for implicit closure #1 in closure #1 in closure #1 in Attribute.init<A>(_:) + 32 (:-1)
54  AttributeGraph                	0x00000001d1644914 AG::ClosureFunctionGU<void, void*, unsigned int>::operator()(void*, unsigned int) const + 12 (:-1)
55  AttributeGraph                	0x00000001d1644914 AG::Graph::UpdateStack::update() + 496 (:-1)
56  AttributeGraph                	0x00000001d164452c AG::Graph::update_attribute(AG::data::ptr<AG::Node>, unsigned int) + 352 (:-1)
57  AttributeGraph                	0x00000001d1643e68 AG::Graph::input_value_ref_slow(AG::data::ptr<AG::Node>, AG::AttributeID, unsigned int, unsigned int, AGSwiftMetadata const*, unsigned char&, long) + 680 (:-1)
58  AttributeGraph                	0x00000001d163e2a8 AG::Graph::input_value_ref(AG::data::ptr<AG::Node>, AG::AttributeID, unsigned int, unsigned int, AGSwiftMetadata const*, unsigned char&) + 128 (:-1)
59  AttributeGraph                	0x00000001d163e2a8 AGGraphGetValue + 232 (:-1)
60  SwiftUICore                   	0x00000001a81c70a8 specialized Attribute.wrappedValue.unsafeAddressor + 52 (:-1)
61  SwiftUICore                   	0x00000001a81c70a8 StaticBody.container.getter + 84 (:-1)
62  SwiftUICore                   	0x00000001a81c6fb0 closure #1 in StaticBody.updateValue() + 436 (:-1)
63  SwiftUICore                   	0x00000001a81c6774 specialized closure #1 in ObservationCenter._withObservation<A>(do:) + 36 (:-1)
64  SwiftUICore                   	0x00000001a81c6774 specialized closure #1 in ObservationCenter._withObservation<A>(do:) + 36 (:-1)
65  SwiftUICore                   	0x00000001a81c6774 specialized withUnsafeMutablePointer<A, B, C>(to:_:) + 36 (:-1)
66  SwiftUICore                   	0x00000001a81c6774 specialized ObservationCenter._withObservation<A>(do:) + 72 (:-1)
67  SwiftUICore                   	0x00000001a81c6774 specialized ObservationCenter._withObservationStashed<A>(do:) + 72 (:-1)
68  SwiftUICore                   	0x00000001a81c6774 specialized ObservationCenter._withObservation<A, B>(attribute:do:) + 112 (:-1)
69  SwiftUICore                   	0x00000001a81c6774 specialized StatefulRule.withObservation<A>(observationCenter:do:) + 140 (:-1)
70  SwiftUICore                   	0x00000001a81c6774 StaticBody.updateValue() + 836 (:-1)
71  SwiftUICore                   	0x00000001a86a3fd0 specialized implicit closure #1 in closure #1 in closure #1 in Attribute.init<A>(_:) + 12 (:-1)
72  SwiftUICore                   	0x00000001a86a3fd0 implicit closure #1 in closure #1 in closure #1 in Attribute.init<A>(_:) + 12 (:-1)
73  SwiftUICore                   	0x00000001a86a3fd0 partial apply for implicit closure #1 in closure #1 in closure #1 in Attribute.init<A>(_:) + 32 (:-1)
74  AttributeGraph                	0x00000001d1644914 AG::ClosureFunctionGU<void, void*, unsigned int>::operator()(void*, unsigned int) const + 12 (:-1)
75  AttributeGraph                	0x00000001d1644914 AG::Graph::UpdateStack::update() + 496 (:-1)
76  AttributeGraph                	0x00000001d164452c AG::Graph::update_attribute(AG::data::ptr<AG::Node>, unsigned int) + 352 (:-1)
123 AttributeGraph                	0x00000001d1643e68 AG::Graph::input_value_ref_slow(AG::data::ptr<AG::Node>, AG::AttributeID, unsigned int, unsigned int, AGSwiftMetadata const*, unsigned char&, long) + 680 (:-1)
124 AttributeGraph                	0x00000001d163e2a8 AG::Graph::input_value_ref(AG::data::ptr<AG::Node>, AG::AttributeID, unsigned int, unsigned int, AGSwiftMetadata const*, unsigned char&) + 128 (:-1)
125 AttributeGraph                	0x00000001d163e2a8 AGGraphGetValue + 232 (:-1)
126 SwiftUICore                   	0x00000001a81d49d0 specialized Attribute.changedValue(options:) + 40 (:-1)
127 SwiftUICore                   	0x00000001a81d49d0 DynamicLayoutViewAdaptor.updatedItems() + 44 (:-1)
128 SwiftUICore                   	0x00000001a81d49d0 protocol witness for DynamicContainerAdaptor.updatedItems() in conformance DynamicLayoutViewAdaptor + 44 (:-1)
129 SwiftUICore                   	0x00000001a81d49d0 specialized DynamicContainerInfo.updateItems(disableTransitions:) + 96 (:-1)
130 SwiftUICore                   	0x00000001a81d5978 specialized DynamicContainerInfo.updateValue() + 452 (:-1)
131 SwiftUICore                   	0x00000001a8b821a8 specialized protocol witness for StatefulRule.updateValue() in conformance DynamicContainerInfo<A> + 8 (:-1)
132 SwiftUICore                   	0x00000001a8b821a8 specialized implicit closure #1 in closure #1 in closure #1 in Attribute.init<A>(_:) + 24 (:-1)
133 AttributeGraph                	0x00000001d1644914 AG::ClosureFunctionGU<void, void*, unsigned int>::operator()(void*, unsigned int) const + 12 (:-1)
134 AttributeGraph                	0x00000001d1644914 AG::Graph::UpdateStack::update() + 496 (:-1)
135 AttributeGraph                	0x00000001d164452c AG::Graph::update_attribute(AG::data::ptr<AG::Node>, unsigned int) + 352 (:-1)
136 AttributeGraph                	0x00000001d1643e68 AG::Graph::input_value_ref_slow(AG::data::ptr<AG::Node>, AG::AttributeID, unsigned int, unsigned int, AGSwiftMetadata const*, unsigned char&, long) + 680 (:-1)
137 AttributeGraph                	0x00000001d163e2a8 AG::Graph::input_value_ref(AG::data::ptr<AG::Node>, AG::AttributeID, unsigned int, unsigned int, AGSwiftMetadata const*, unsigned char&) + 128 (:-1)
138 AttributeGraph                	0x00000001d163e2a8 AGGraphGetValue + 232 (:-1)
139 SwiftUICore                   	0x00000001a81d3ebc specialized OptionalAttribute.wrappedValue.getter + 60 (:-1)
140 SwiftUICore                   	0x00000001a81d3ebc DynamicPreferenceCombiner.info.getter + 88 (:-1)
141 SwiftUICore                   	0x00000001a81d406c DynamicPreferenceCombiner.value.getter + 220 (:-1)
142 SwiftUICore                   	0x00000001a89430ac specialized implicit closure #1 in closure #1 in closure #1 in Attribute.init<A>(_:) + 260 (:-1)
143 SwiftUICore                   	0x00000001a89430ac implicit closure #1 in closure #1 in closure #1 in Attribute.init<A>(_:) + 324 (:-1)
144 AttributeGraph                	0x00000001d1644914 AG::ClosureFunctionGU<void, void*, unsigned int>::operator()(void*, unsigned int) const + 12 (:-1)
145 AttributeGraph                	0x00000001d1644914 AG::Graph::UpdateStack::update() + 496 (:-1)
146 AttributeGraph                	0x00000001d164452c AG::Graph::update_attribute(AG::data::ptr<AG::Node>, unsigned int) + 352 (:-1)
147 AttributeGraph                	0x00000001d1643e68 AG::Graph::input_value_ref_slow(AG::data::ptr<AG::Node>, AG::AttributeID, unsigned int, unsigned int, AGSwiftMetadata const*, unsigned char&, long) + 680 (:-1)
148 AttributeGraph                	0x00000001d163e2a8 AG::Graph::input_value_ref(AG::data::ptr<AG::Node>, AG::AttributeID, unsigned int, unsigned int, AGSwiftMetadata const*, unsigned char&) + 128 (:-1)
149 AttributeGraph                	0x00000001d163e2a8 AGGraphGetValue + 232 (:-1)
150 SwiftUICore                   	0x00000001a8220bc8 specialized Attribute.wrappedValue.unsafeAddressor + 52 (:-1)
151 SwiftUICore                   	0x00000001a8220bc8 PairPreferenceCombiner.value.getter + 100 (:-1)
152 SwiftUICore                   	0x00000001a89430ac specialized implicit closure #1 in closure #1 in closure #1 in Attribute.init<A>(_:) + 260 (:-1)
153 SwiftUICore                   	0x00000001a89430ac implicit closure #1 in closure #1 in closure #1 in Attribute.init<A>(_:) + 324 (:-1)
154 AttributeGraph                	0x00000001d1644914 AG::ClosureFunctionGU<void, void*, unsigned int>::operator()(void*, unsigned int) const + 12 (:-1)
155 AttributeGraph                	0x00000001d1644914 AG::Graph::UpdateStack::update() + 496 (:-1)
156 AttributeGraph                	0x00000001d164452c AG::Graph::update_attribute(AG::data::ptr<AG::Node>, unsigned int) + 352 (:-1)
157 AttributeGraph                	0x00000001d163e560 AG::Graph::value_ref(AG::AttributeID, unsigned int, AGSwiftMetadata const*, unsigned char&) + 296 (:-1)
158 AttributeGraph                	0x00000001d1646cbc AGGraphGetWeakValue + 372 (:-1)
159 SwiftUICore                   	0x00000001a81cd360 specialized WeakAttribute.wrappedValue.getter + 16 (:-1)
160 SwiftUICore                   	0x00000001a81cd360 GraphHost.preferenceValues() + 48 (:-1)
161 SwiftUICore                   	0x00000001a81cd360 GraphHost.preferenceValue<A>(_:) + 556 (:-1)
162 SwiftUICore                   	0x00000001a81cd128 closure #1 in ViewGraphRootValueUpdater._preferenceValue<A>(_:) + 8 (:-1)
163 SwiftUICore                   	0x00000001a81cd128 partial apply for closure #1 in ViewGraphRootValueUpdater._preferenceValue<A>(_:) + 36 (:-1)
164 SwiftUICore                   	0x00000001a81be934 closure #1 in ViewGraphRootValueUpdater._updateViewGraph<A>(body:) + 36 (:-1)
165 SwiftUICore                   	0x00000001a81be934 specialized static AGGraphRef.withoutUpdate<A>(_:) + 44 (:-1)
166 SwiftUICore                   	0x00000001a81be934 ViewGraphRootValueUpdater._updateViewGraph<A>(body:) + 232 (:-1)
167 SwiftUICore                   	0x00000001a81cd000 ViewGraphRootValueUpdater._preferenceValue<A>(_:) + 312 (:-1)
168 SwiftUI                       	0x00000001a7081c80 specialized ViewRendererHost.preferenceValue<A>(_:) + 44 (:-1)
169 SwiftUI                       	0x00000001a7081c80 specialized PresentationHostingController.setupDelayIfNeeded() + 148 (:-1)
170 SwiftUI                       	0x00000001a7083018 SheetBridge.present(_:from:animated:existingPresentedVC:isPreempting:) + 748 (:-1)
171 SwiftUI                       	0x00000001a70739c8 SheetBridge.contingentlyPresent(_:from:animated:) + 1076 (:-1)
172 SwiftUI                       	0x00000001a6ef6c20 specialized SheetBridge.preferencesDidChange(_:) + 2932 (:-1)
173 SwiftUI                       	0x00000001a6ef245c _UIHostingView.preferencesDidChange() + 780 (:-1)
174 SwiftUICore                   	0x00000001a8ea263c specialized update #1 () in ViewGraph.updateOutputs(async:) + 332 (:-1)
175 SwiftUICore                   	0x00000001a81c2ef8 ViewGraph.updateOutputs(async:) + 244 (:-1)
176 SwiftUICore                   	0x00000001a81c2ef8 ViewGraph.updateOutputs(at:) + 472 (:-1)
177 SwiftUICore                   	0x00000001a81c0bd0 closure #2 in closure #1 in ViewGraphRootValueUpdater.render(interval:updateDisplayList:targetTimestamp:) + 44 (:-1)
178 SwiftUICore                   	0x00000001a81c0bd0 closure #1 in ViewGraphRootValueUpdater.render(interval:updateDisplayList:targetTimestamp:) + 872 (:-1)
179 SwiftUICore                   	0x00000001a81c0818 ViewGraphRootValueUpdater.render(interval:updateDisplayList:targetTimestamp:) + 584 (:-1)
180 UIKitCore                     	0x00000001a3c62d04 UIHostingViewBase.layoutSubviews() + 424 (:-1)
181 SwiftUI                       	0x00000001a6ee9bbc _UIHostingView.layoutSubviews() + 116 (:-1)
182 SwiftUI                       	0x00000001a6ee9b24 @objc _UIHostingView.layoutSubviews() + 36 (:-1)
183 UIKitCore                     	0x00000001a3ac81a0 closure #1 in UIView._layoutSubviewsWithObservationTracking() + 8 (:-1)
184 UIKitCore                     	0x00000001a3ac81a0 specialized closure #1 in _withObservation<A>(do:) + 40 (:-1)
185 UIKitCore                     	0x00000001a3ac81a0 specialized closure #1 in _withObservation<A>(do:) + 40 (:-1)
186 UIKitCore                     	0x00000001a3ac81a0 specialized withUnsafeMutablePointer<A, B, C>(to:_:) + 40 (:-1)
187 UIKitCore                     	0x00000001a3ac81a0 specialized _withObservation<A>(do:) + 92 (:-1)
188 UIKitCore                     	0x00000001a3ac81a0 specialized withObservation<A, B>(by:of:_:do:onChange:) + 112 (:-1)
189 UIKitCore                     	0x00000001a3ac81a0 UIView._layoutSubviewsWithObservationTracking() + 688 (:-1)
190 UIKitCore                     	0x00000001a3ac8aec @objc UIView._layoutSubviewsWithObservationTracking() + 36 (:-1)
191 UIKitCore                     	0x00000001a3ac70a0 -[UIView(CALayerDelegate) layoutSublayersOfLayer:] + 2684 (:-1)
192 QuartzCore                    	0x000000019eae88a4 CA::Layer::perform_update_(CA::Layer*, CALayer*, unsigned int, CA::LayerUpdateReason, CA::Transaction*) + 460 (:-1)
193 QuartzCore                    	0x000000019eae83f4 CA::Layer::update_if_needed(CA::Transaction*, unsigned int, unsigned int, CA::LayerUpdateReason) + 512 (:-1)
194 QuartzCore                    	0x000000019eae83f4 CA::Layer::update_if_needed_(CA::Transaction*, CA::LayerUpdateReason) + 664 (:-1)
195 QuartzCore                    	0x000000019e8da800 CA::Layer::layout_and_display_if_needed(CA::Transaction*) + 180 (:-1)
196 QuartzCore                    	0x000000019e899198 CA::Context::commit_transaction(CA::Transaction*, double, double*) + 560 (:-1)
197 QuartzCore                    	0x000000019e8c5520 CA::Transaction::commit() + 620 (:-1)
198 QuartzCore                    	0x000000019e8d4074 CA::Transaction::flush_as_runloop_observer(bool) + 88 (:-1)
199 UIKitCore                     	0x00000001a3b625f0 _UIApplicationFlushCATransaction + 52 (:-1)
200 UIKitCore                     	0x00000001a3b62524 performCATransactionCommitAction + 308 (:-1)
201 UIKitCore                     	0x00000001a3b62524 __setupUpdateSequence_block_invoke_2 + 352 (:-1)
202 UIKitCore                     	0x00000001a3b7b6d4 _UIUpdateSequenceRunNext + 128 (:-1)
203 UIKitCore                     	0x00000001a3b78c60 schedulerStepScheduledMainSectionContinue + 60 (:-1)
204 UpdateCycle                   	0x00000002b2cd056c UC::DriverCore::continueProcessing() + 84 (:-1)
205 CoreFoundation                	0x000000019dedf390 __CFRUNLOOP_IS_CALLING_OUT_TO_A_SOURCE0_PERFORM_FUNCTION__ + 28 (:-1)
206 CoreFoundation                	0x000000019dedf304 __CFRunLoopDoSource0 + 172 (:-1)
207 CoreFoundation                	0x000000019dea45d8 __CFRunLoopDoSources0 + 232 (:-1)
208 CoreFoundation                	0x000000019de6e1a0 __CFRunLoopRun + 820 (:-1)
209 CoreFoundation                	0x000000019de6d54c _CFRunLoopRunSpecificWithOptions + 532 (:-1)
210 GraphicsServices              	0x0000000243a19498 GSEventRunModal + 120 (:-1)
211 UIKitCore                     	0x00000001a3ba1670 -[UIApplication _run] + 796 (:-1)
212 UIKitCore                     	0x00000001a3b0c158 UIApplicationMain + 332 (:-1)
213 SwiftUI                       	0x00000001a6efb570 closure #1 in KitRendererCommon(_:) + 168 (:-1)
214 SwiftUI                       	0x00000001a6ef80f4 specialized UnsafeMutablePointer<>.withMemoryRebound<A, B, C>(to:capacity:_:) + 12 (:-1)
215 SwiftUI                       	0x00000001a6ef80f4 KitRendererCommon(_:) + 16 (:-1)
216 SwiftUI                       	0x00000001a6ef80f4 runApp<A>(_:) + 112 (:-1)
217 SwiftUI                       	0x00000001a6ef7c48 static App.main() + 172 (:-1)
218 CatchWords                    	0x00000001054cd390 static CatchWordsApp.$main() + 52 (CatchWordsApp.swift:0)
219 CatchWords                    	0x00000001054cd390 main + 64
220 dyld                          	0x000000019aa79c1c start + 6928 (:-1)

Thread 1:
0   libsystem_kernel.dylib        	0x000000024d44a808 __semwait_signal + 8 (:-1)
1   libsystem_c.dylib             	0x00000001a99c882c nanosleep + 220 (:-1)
2   libsystem_c.dylib             	0x00000001a99c8954 sleep + 52 (:-1)
3   CatchWords                    	0x0000000105728c54 monitorThreadCache + 220
4   libsystem_pthread.dylib       	0x00000001fd736438 _pthread_start + 136 (:-1)
5   libsystem_pthread.dylib       	0x00000001fd7328cc thread_start + 8 (:-1)

Thread 2 name:
Thread 2:
0   libsystem_kernel.dylib        	0x000000024d444cd4 mach_msg2_trap + 8 (:-1)
1   libsystem_kernel.dylib        	0x000000024d44830c mach_msg2_internal + 76 (:-1)
2   libsystem_kernel.dylib        	0x000000024d44822c mach_msg2 + 4 (:-1)
3   libsystem_kernel.dylib        	0x000000024d44822c mach_msg_overwrite + 424 (:-1)
4   libsystem_kernel.dylib        	0x000000024d448078 mach_msg + 24 (:-1)
5   CatchWords                    	0x0000000105712b24 handleExceptions + 160
6   libsystem_pthread.dylib       	0x00000001fd736438 _pthread_start + 136 (:-1)
7   libsystem_pthread.dylib       	0x00000001fd7328cc thread_start + 8 (:-1)

Thread 3 name:
Thread 3:
0   libsystem_kernel.dylib        	0x000000024d44a808 __semwait_signal + 8 (:-1)
1   libsystem_c.dylib             	0x00000001a99c882c nanosleep + 220 (:-1)
2   Foundation                    	0x000000019b3e5508 +[NSThread sleepForTimeInterval:] + 152 (:-1)
3   CatchWords                    	0x00000001057c8ab0 SentryANRTrackerV2.detectANRs() + 824
4   CatchWords                    	0x0000000104dd7e78 <deduplicated_symbol> + 36
5   Foundation                    	0x000000019bb02f2c __NSThread__block_start__ + 76 (:-1)
6   libsystem_pthread.dylib       	0x00000001fd736438 _pthread_start + 136 (:-1)
7   libsystem_pthread.dylib       	0x00000001fd7328cc thread_start + 8 (:-1)

Thread 4 name:
Thread 4:
0   libsystem_kernel.dylib        	0x000000024d444cd4 mach_msg2_trap + 8 (:-1)
1   libsystem_kernel.dylib        	0x000000024d44830c mach_msg2_internal + 76 (:-1)
2   libsystem_kernel.dylib        	0x000000024d44822c mach_msg2 + 4 (:-1)
3   libsystem_kernel.dylib        	0x000000024d44822c mach_msg_overwrite + 424 (:-1)
4   libsystem_kernel.dylib        	0x000000024d448078 mach_msg + 24 (:-1)
5   CoreFoundation                	0x000000019dea4374 __CFRunLoopServiceMachPort + 160 (:-1)
6   CoreFoundation                	0x000000019de6e310 __CFRunLoopRun + 1188 (:-1)
7   CoreFoundation                	0x000000019de6d54c _CFRunLoopRunSpecificWithOptions + 532 (:-1)
8   Foundation                    	0x000000019b0dacf0 -[NSRunLoop(NSRunLoop) runMode:beforeDate:] + 212 (:-1)
9   Foundation                    	0x000000019b0dabd8 -[NSRunLoop(NSRunLoop) runUntilDate:] + 64 (:-1)
10  UIKitCore                     	0x00000001a3b66eac -[UIEventFetcher threadMain] + 420 (:-1)
11  Foundation                    	0x000000019b15e914 __NSThread__start__ + 732 (:-1)
12  libsystem_pthread.dylib       	0x00000001fd736438 _pthread_start + 136 (:-1)
13  libsystem_pthread.dylib       	0x00000001fd7328cc thread_start + 8 (:-1)

Thread 5 name:
Thread 5:
0   libsystem_kernel.dylib        	0x000000024d444c50 semaphore_wait_trap + 8 (:-1)
1   caulk                         	0x00000002b7b08c6c caulk::mach::semaphore::wait_or_error() + 8 (:-1)
2   caulk                         	0x00000002b7b08c6c caulk::semaphore::timed_wait(double) + 224 (:-1)
3   caulk                         	0x00000002b7b08cb8 caulk::semaphore::wait() + 12 (:-1)
4   caulk                         	0x00000002b7b08cb8 caulk::concurrent::details::worker_thread::run() + 32 (:-1)
5   caulk                         	0x00000002b7b0cf54 std::__1::__invoke_result_impl<void, void (caulk::concurrent::details::worker_thread::*&)(), caulk::concurrent::details::worker_thread*&>::type std::__1::__invoke[abi:nqe210106]<void (caulk::concur... + 72 (:-1)
6   caulk                         	0x00000002b7b0cf54 decltype(auto) std::__1::__apply_tuple_impl[abi:nqe210106]<void (caulk::concurrent::details::worker_thread::*&)(), std::__1::tuple<caulk::concurrent::details::worker_thread*>&, 0ul>(void (caulk::co... + 72 (:-1)
7   caulk                         	0x00000002b7b0cf54 decltype(auto) std::__1::apply[abi:nqe210106]<void (caulk::concurrent::details::worker_thread::*&)(), std::__1::tuple<caulk::concurrent::details::worker_thread*>&>(void (caulk::concurrent::details:... + 72 (:-1)
8   caulk                         	0x00000002b7b0cf54 void* caulk::thread_proxy<std::__1::tuple<caulk::thread::attributes, void (caulk::concurrent::details::worker_thread::*)(), std::__1::tuple<caulk::concurrent::details::worker_thread*>>>(void*) + 96 (:-1)
9   libsystem_pthread.dylib       	0x00000001fd736438 _pthread_start + 136 (:-1)
10  libsystem_pthread.dylib       	0x00000001fd7328cc thread_start + 8 (:-1)

Thread 6 name:
Thread 6:
0   libsystem_kernel.dylib        	0x000000024d444c50 semaphore_wait_trap + 8 (:-1)
1   caulk                         	0x00000002b7b08c6c caulk::mach::semaphore::wait_or_error() + 8 (:-1)
2   caulk                         	0x00000002b7b08c6c caulk::semaphore::timed_wait(double) + 224 (:-1)
3   caulk                         	0x00000002b7b08cb8 caulk::semaphore::wait() + 12 (:-1)
4   caulk                         	0x00000002b7b08cb8 caulk::concurrent::details::worker_thread::run() + 32 (:-1)
5   caulk                         	0x00000002b7b0cf54 std::__1::__invoke_result_impl<void, void (caulk::concurrent::details::worker_thread::*&)(), caulk::concurrent::details::worker_thread*&>::type std::__1::__invoke[abi:nqe210106]<void (caulk::concur... + 72 (:-1)
6   caulk                         	0x00000002b7b0cf54 decltype(auto) std::__1::__apply_tuple_impl[abi:nqe210106]<void (caulk::concurrent::details::worker_thread::*&)(), std::__1::tuple<caulk::concurrent::details::worker_thread*>&, 0ul>(void (caulk::co... + 72 (:-1)
7   caulk                         	0x00000002b7b0cf54 decltype(auto) std::__1::apply[abi:nqe210106]<void (caulk::concurrent::details::worker_thread::*&)(), std::__1::tuple<caulk::concurrent::details::worker_thread*>&>(void (caulk::concurrent::details:... + 72 (:-1)
8   caulk                         	0x00000002b7b0cf54 void* caulk::thread_proxy<std::__1::tuple<caulk::thread::attributes, void (caulk::concurrent::details::worker_thread::*)(), std::__1::tuple<caulk::concurrent::details::worker_thread*>>>(void*) + 96 (:-1)
9   libsystem_pthread.dylib       	0x00000001fd736438 _pthread_start + 136 (:-1)
10  libsystem_pthread.dylib       	0x00000001fd7328cc thread_start + 8 (:-1)

Thread 7 name:
Thread 7:
0   libsystem_kernel.dylib        	0x000000024d444cd4 mach_msg2_trap + 8 (:-1)
1   libsystem_kernel.dylib        	0x000000024d44830c mach_msg2_internal + 76 (:-1)
2   libsystem_kernel.dylib        	0x000000024d44822c mach_msg2 + 4 (:-1)
3   libsystem_kernel.dylib        	0x000000024d44822c mach_msg_overwrite + 424 (:-1)
4   libsystem_kernel.dylib        	0x000000024d448078 mach_msg + 24 (:-1)
5   CoreFoundation                	0x000000019dea4374 __CFRunLoopServiceMachPort + 160 (:-1)
6   CoreFoundation                	0x000000019de6e310 __CFRunLoopRun + 1188 (:-1)
7   CoreFoundation                	0x000000019de6d54c _CFRunLoopRunSpecificWithOptions + 532 (:-1)
8   CFNetwork                     	0x00000001b337db54 -[__CFN_CoreSchedulingSetRunnable runForever] + 24 (:-1)
9   CFNetwork                     	0x00000001b337db54 +[__CFN_CoreSchedulingSetRunnable _run:] + 416 (:-1)
10  Foundation                    	0x000000019b15e914 __NSThread__start__ + 732 (:-1)
11  libsystem_pthread.dylib       	0x00000001fd736438 _pthread_start + 136 (:-1)
12  libsystem_pthread.dylib       	0x00000001fd7328cc thread_start + 8 (:-1)

Thread 8 name:
Thread 8:
0   libsystem_kernel.dylib        	0x000000024d444c50 semaphore_wait_trap + 8 (:-1)
1   caulk                         	0x00000002b7b08c6c caulk::mach::semaphore::wait_or_error() + 8 (:-1)
2   caulk                         	0x00000002b7b08c6c caulk::semaphore::timed_wait(double) + 224 (:-1)
3   caulk                         	0x00000002b7b08cb8 caulk::semaphore::wait() + 12 (:-1)
4   caulk                         	0x00000002b7b08cb8 caulk::concurrent::details::worker_thread::run() + 32 (:-1)
5   caulk                         	0x00000002b7b0cf54 std::__1::__invoke_result_impl<void, void (caulk::concurrent::details::worker_thread::*&)(), caulk::concurrent::details::worker_thread*&>::type std::__1::__invoke[abi:nqe210106]<void (caulk::concur... + 72 (:-1)
6   caulk                         	0x00000002b7b0cf54 decltype(auto) std::__1::__apply_tuple_impl[abi:nqe210106]<void (caulk::concurrent::details::worker_thread::*&)(), std::__1::tuple<caulk::concurrent::details::worker_thread*>&, 0ul>(void (caulk::co... + 72 (:-1)
7   caulk                         	0x00000002b7b0cf54 decltype(auto) std::__1::apply[abi:nqe210106]<void (caulk::concurrent::details::worker_thread::*&)(), std::__1::tuple<caulk::concurrent::details::worker_thread*>&>(void (caulk::concurrent::details:... + 72 (:-1)
8   caulk                         	0x00000002b7b0cf54 void* caulk::thread_proxy<std::__1::tuple<caulk::thread::attributes, void (caulk::concurrent::details::worker_thread::*)(), std::__1::tuple<caulk::concurrent::details::worker_thread*>>>(void*) + 96 (:-1)
9   libsystem_pthread.dylib       	0x00000001fd736438 _pthread_start + 136 (:-1)
10  libsystem_pthread.dylib       	0x00000001fd7328cc thread_start + 8 (:-1)

Thread 9 name:
Thread 9:
0   libsystem_kernel.dylib        	0x000000024d444c50 semaphore_wait_trap + 8 (:-1)
1   WebKit                        	0x00000001ba427194 IPC::Semaphore::wait() + 8 (:-1)
2   WebKit                        	0x00000001ba427194 IPC::StreamConnectionWorkQueue::startProcessingThread()::$_0::operator()() + 24 (:-1)
3   WebKit                        	0x00000001ba427194 WTF::Detail::CallableWrapper<IPC::StreamConnectionWorkQueue::startProcessingThread()::$_0, void>::call() + 52 (:-1)
4   JavaScriptCore                	0x00000001b378fef0 WTF::Function<void ()>::operator()() const + 32 (:-1)
5   JavaScriptCore                	0x00000001b378fef0 WTF::Thread::entryPoint(WTF::Thread::NewThreadContext*) + 356 (:-1)
6   JavaScriptCore                	0x00000001b37936a8 WTF::wtfThreadEntryPoint(void*) + 16 (:-1)
7   libsystem_pthread.dylib       	0x00000001fd736438 _pthread_start + 136 (:-1)
8   libsystem_pthread.dylib       	0x00000001fd7328cc thread_start + 8 (:-1)

Thread 10 name:
Thread 10:
0   libsystem_kernel.dylib        	0x000000024d444cd4 mach_msg2_trap + 8 (:-1)
1   libsystem_kernel.dylib        	0x000000024d44830c mach_msg2_internal + 76 (:-1)
2   libsystem_kernel.dylib        	0x000000024d44822c mach_msg2 + 4 (:-1)
3   libsystem_kernel.dylib        	0x000000024d44822c mach_msg_overwrite + 424 (:-1)
4   libsystem_kernel.dylib        	0x000000024d448078 mach_msg + 24 (:-1)
5   CoreFoundation                	0x000000019dea4374 __CFRunLoopServiceMachPort + 160 (:-1)
6   CoreFoundation                	0x000000019de6e310 __CFRunLoopRun + 1188 (:-1)
7   CoreFoundation                	0x000000019de6d54c _CFRunLoopRunSpecificWithOptions + 532 (:-1)
8   CoreFoundation                	0x000000019df1dde4 CFRunLoopRun + 64 (:-1)
9   ANEServices                   	0x00000001dda698f0 ANE::ANEServicesThreadStart(ANE::ANEServicesThreadParams*) + 152 (:-1)
10  libsystem_pthread.dylib       	0x00000001fd736438 _pthread_start + 136 (:-1)
11  libsystem_pthread.dylib       	0x00000001fd7328cc thread_start + 8 (:-1)

Thread 11 name:
Thread 11:
0   libsystem_kernel.dylib        	0x000000024d444cd4 mach_msg2_trap + 8 (:-1)
1   libsystem_kernel.dylib        	0x000000024d44830c mach_msg2_internal + 76 (:-1)
2   libsystem_kernel.dylib        	0x000000024d44822c mach_msg2 + 4 (:-1)
3   libsystem_kernel.dylib        	0x000000024d44822c mach_msg_overwrite + 424 (:-1)
4   libsystem_kernel.dylib        	0x000000024d448078 mach_msg + 24 (:-1)
5   CoreFoundation                	0x000000019dea4374 __CFRunLoopServiceMachPort + 160 (:-1)
6   CoreFoundation                	0x000000019de6e310 __CFRunLoopRun + 1188 (:-1)
7   CoreFoundation                	0x000000019de6d54c _CFRunLoopRunSpecificWithOptions + 532 (:-1)
8   CoreFoundation                	0x000000019df1dde4 CFRunLoopRun + 64 (:-1)
9   ANEServices                   	0x00000001dda698f0 ANE::ANEServicesThreadStart(ANE::ANEServicesThreadParams*) + 152 (:-1)
10  libsystem_pthread.dylib       	0x00000001fd736438 _pthread_start + 136 (:-1)
11  libsystem_pthread.dylib       	0x00000001fd7328cc thread_start + 8 (:-1)

Thread 12 name:
Thread 12:
0   libsystem_kernel.dylib        	0x000000024d444cd4 mach_msg2_trap + 8 (:-1)
1   libsystem_kernel.dylib        	0x000000024d44830c mach_msg2_internal + 76 (:-1)
2   libsystem_kernel.dylib        	0x000000024d44822c mach_msg2 + 4 (:-1)
3   libsystem_kernel.dylib        	0x000000024d44822c mach_msg_overwrite + 424 (:-1)
4   libsystem_kernel.dylib        	0x000000024d448078 mach_msg + 24 (:-1)
5   CoreFoundation                	0x000000019dea4374 __CFRunLoopServiceMachPort + 160 (:-1)
6   CoreFoundation                	0x000000019de6e310 __CFRunLoopRun + 1188 (:-1)
7   CoreFoundation                	0x000000019de6d54c _CFRunLoopRunSpecificWithOptions + 532 (:-1)
8   CoreFoundation                	0x000000019df1dde4 CFRunLoopRun + 64 (:-1)
9   ANEServices                   	0x00000001dda698f0 ANE::ANEServicesThreadStart(ANE::ANEServicesThreadParams*) + 152 (:-1)
10  libsystem_pthread.dylib       	0x00000001fd736438 _pthread_start + 136 (:-1)
11  libsystem_pthread.dylib       	0x00000001fd7328cc thread_start + 8 (:-1)

Thread 13 name:
Thread 13:
0   libsystem_kernel.dylib        	0x000000024d444c50 semaphore_wait_trap + 8 (:-1)
1   libdispatch.dylib             	0x00000001d8968410 _dispatch_sema4_wait + 28 (:-1)
2   libdispatch.dylib             	0x00000001d8968aa0 _dispatch_semaphore_wait_slow + 132 (:-1)
3   UIKitCore                     	0x00000001a3e5a1f8 0x1a3a80000 + 4039160
4   UIKitCore                     	0x00000001a3e5a1b0 closure #2 in InProcessAnimationManager.startAdvancing(_:) + 308 (:-1)
5   UIKitCore                     	0x00000001a3ac05c4 <deduplicated_symbol> + 36 (:-1)
6   Foundation                    	0x000000019b15e914 __NSThread__start__ + 732 (:-1)
7   libsystem_pthread.dylib       	0x00000001fd736438 _pthread_start + 136 (:-1)
8   libsystem_pthread.dylib       	0x00000001fd7328cc thread_start + 8 (:-1)

Thread 14 name:
Thread 14:
0   libsystem_kernel.dylib        	0x000000024d444cd4 mach_msg2_trap + 8 (:-1)
1   libsystem_kernel.dylib        	0x000000024d44830c mach_msg2_internal + 76 (:-1)
2   libsystem_kernel.dylib        	0x000000024d44822c mach_msg2 + 4 (:-1)
3   libsystem_kernel.dylib        	0x000000024d44822c mach_msg_overwrite + 424 (:-1)
4   libsystem_kernel.dylib        	0x000000024d448078 mach_msg + 24 (:-1)
5   CoreFoundation                	0x000000019dea4374 __CFRunLoopServiceMachPort + 160 (:-1)
6   CoreFoundation                	0x000000019de6e310 __CFRunLoopRun + 1188 (:-1)
7   CoreFoundation                	0x000000019de6d54c _CFRunLoopRunSpecificWithOptions + 532 (:-1)
8   CoreFoundation                	0x000000019df1dde4 CFRunLoopRun + 64 (:-1)
9   ANEServices                   	0x00000001dda698f0 ANE::ANEServicesThreadStart(ANE::ANEServicesThreadParams*) + 152 (:-1)
10  libsystem_pthread.dylib       	0x00000001fd736438 _pthread_start + 136 (:-1)
11  libsystem_pthread.dylib       	0x00000001fd7328cc thread_start + 8 (:-1)

Thread 15 name:
Thread 15:
0   libsystem_kernel.dylib        	0x000000024d444cd4 mach_msg2_trap + 8 (:-1)
1   libsystem_kernel.dylib        	0x000000024d44830c mach_msg2_internal + 76 (:-1)
2   libsystem_kernel.dylib        	0x000000024d44822c mach_msg2 + 4 (:-1)
3   libsystem_kernel.dylib        	0x000000024d44822c mach_msg_overwrite + 424 (:-1)
4   libsystem_kernel.dylib        	0x000000024d448078 mach_msg + 24 (:-1)
5   CoreFoundation                	0x000000019dea4374 __CFRunLoopServiceMachPort + 160 (:-1)
6   CoreFoundation                	0x000000019de6e310 __CFRunLoopRun + 1188 (:-1)
7   CoreFoundation                	0x000000019de6d54c _CFRunLoopRunSpecificWithOptions + 532 (:-1)
8   Foundation                    	0x000000019b0dacf0 -[NSRunLoop(NSRunLoop) runMode:beforeDate:] + 212 (:-1)
9   Foundation                    	0x000000019b0df2fc -[NSRunLoop(NSRunLoop) run] + 64 (:-1)
10  SwiftUICore                   	0x00000001a83d3658 specialized static ViewGraphDisplayLink.asyncThread(arg:) + 760 (:-1)
11  SwiftUICore                   	0x00000001a83d3348 static ViewGraphDisplayLink.asyncThread(arg:) + 8 (:-1)
12  SwiftUICore                   	0x00000001a83d3348 @objc static ViewGraphDisplayLink.asyncThread(arg:) + 72 (:-1)
13  Foundation                    	0x000000019b15e914 __NSThread__start__ + 732 (:-1)
14  libsystem_pthread.dylib       	0x00000001fd736438 _pthread_start + 136 (:-1)
15  libsystem_pthread.dylib       	0x00000001fd7328cc thread_start + 8 (:-1)

Thread 16:

Thread 17:

Thread 18:

Thread 19:


Thread 0 crashed with ARM Thread State (64-bit):
    x0: 0x000000015d82b848   x1: 0x0000000200000003   x2: 0x0000000000000060   x3: 0xfffff0007fc00000
    x4: 0x0000000133100880   x5: 0x0000000000000013   x6: 0x0000000000000020   x7: 0xfffff0003ffff800
    x8: 0xfffffffe00000000   x9: 0x00000000ffbe877d  x10: 0x0000000000000000  x11: 0x0000000000000000
   x12: 0x0473739b00417882  x13: 0x0473629900417280  x14: 0x0000000000017800  x15: 0x0000000106624000
   x16: 0x0000000200000003  x17: 0x0000000000000003  x18: 0x0000000000000000  x19: 0xe900000000000072
   x20: 0x000000016b0d0250  x21: 0xe900000000000072  x22: 0xd00000000000001d  x23: 0x000000020a0c4af8
   x24: 0x000000013c307930  x25: 0x000000016b0d02d0  x26: 0x00000001a827f184  x27: 0x000000020a0db340
   x28: 0x000000013c307910   fp: 0x000000016b0d0230   lr: 0x000000019ad3c878
    sp: 0x000000016b0d01b0   pc: 0x000000019ad3c878 cpsr: 0x60000000
   esr: 0xf2000001 (Breakpoint) brk 1


Binary Images:
        0x104d24000 -         0x105c77fff CatchWords arm64  <033c175fe4923129bd3152859afdc95e> /private/var/containers/Bundle/Application/0FD6307B-76F0-4752-81A7-87E06B1D8AF2/CatchWords.app/CatchWords
        0x106048000 -         0x106053fff libobjc-trampolines.dylib arm64e  <004ce93cf1423d68b3c330c6efef4d65> /private/preboot/Cryptexes/OS/usr/lib/libobjc-trampolines.dylib
        0x19aa75000 -         0x19ab1a47f dyld arm64e  <0f8d35b6556f3e348eaa80ab54047dc5> /usr/lib/dyld
        0x19ab36000 -         0x19b0cf8bf libswiftCore.dylib arm64e  <1539faa731da3c41b14aa9691063824d> /usr/lib/swift/libswiftCore.dylib
        0x19b0d0000 -         0x19bf59cbf Foundation arm64e  <73841aa3bfdd322d8dc2e5185a14dee1> /System/Library/Frameworks/Foundation.framework/Foundation
        0x19de3f000 -         0x19e3dba3f CoreFoundation arm64e  <101eb2f1191534a08bc9631d03753b84> /System/Library/Frameworks/CoreFoundation.framework/CoreFoundation
        0x19e82b000 -         0x19ec1bebf QuartzCore arm64e  <8f1e0b3fadd63710a790009333597ab4> /System/Library/Frameworks/QuartzCore.framework/QuartzCore
        0x1a3a80000 -         0x1a5fc363f UIKitCore arm64e  <0d94422ffe7c302eb8963bc5873c0cfc> /System/Library/PrivateFrameworks/UIKitCore.framework/UIKitCore
        0x1a6ecb000 -         0x1a815699f SwiftUI arm64e  <17adc54e93ab3f13b469e3f53181fc4d> /System/Library/Frameworks/SwiftUI.framework/SwiftUI
        0x1a81a4000 -         0x1a90a07bf SwiftUICore arm64e  <82a21ce44e4338fb9862f0be7b909df1> /System/Library/Frameworks/SwiftUICore.framework/SwiftUICore
        0x1a99bc000 -         0x1a9a3b5ff libsystem_c.dylib arm64e  <ff42982180de3a6899cb0b2e707e8d48> /usr/lib/system/libsystem_c.dylib
        0x1b32ec000 -         0x1b369c77f CFNetwork arm64e  <3ae849fe8a7d388c86ef64dedb9fc5c6> /System/Library/Frameworks/CFNetwork.framework/CFNetwork
        0x1b369d000 -         0x1b555ee5f JavaScriptCore arm64e  <f79060281c6d3b4cbd9378c196c83a83> /System/Library/Frameworks/JavaScriptCore.framework/JavaScriptCore
        0x1b914e000 -         0x1ba8ce9df WebKit arm64e  <c39bd22c347538af91bd0b7574081011> /System/Library/Frameworks/WebKit.framework/WebKit
        0x1d1638000 -         0x1d167d19f AttributeGraph arm64e  <a973ad423cff3c90bc78e4e0bffa155b> /System/Library/PrivateFrameworks/AttributeGraph.framework/AttributeGraph
        0x1d8965000 -         0x1d89ab5ff libdispatch.dylib arm64e  <49c0cd3ea6963b11ba925755f0c3c6e3> /usr/lib/system/libdispatch.dylib
        0x1dda46000 -         0x1dda7689f ANEServices arm64e  <a1b9a671516030629696e471e4b7e6ca> /System/Library/PrivateFrameworks/ANEServices.framework/ANEServices
        0x1fd732000 -         0x1fd73e4ef libsystem_pthread.dylib arm64e  <34b44744bc64386eab90eee86b23ac46> /usr/lib/system/libsystem_pthread.dylib
        0x243a18000 -         0x243a207bf GraphicsServices arm64e  <411165e2ee8e380eb2549977273971e3> /System/Library/PrivateFrameworks/GraphicsServices.framework/GraphicsServices
        0x24d444000 -         0x24d47fb1f libsystem_kernel.dylib arm64e  <18665b3f6d5133abb9e963062200ec42> /usr/lib/system/libsystem_kernel.dylib
        0x2b2ccf000 -         0x2b2cd11bf UpdateCycle arm64e  <26fab8144c8f3a06b45ecba271020dc4> /System/Library/PrivateFrameworks/UpdateCycle.framework/UpdateCycle
        0x2b7b05000 -         0x2b7b2e01f caulk arm64e  <5dd354fba86f37328f36a88736414f79> /System/Library/PrivateFrameworks/caulk.framework/caulk

EOF
```

## 3. 2026-11-02T08:59:57.243Z  ビルド 1.0.4 (1075)
- deviceModel: iPad16_3
- deviceFamily: IPAD
- osVersion: 26.6.1
- appPlatform: IOS
- architecture: arm64e
- locale: ja-TW
- diskBytesAvailable: 159850434560
- batteryPercentage: 85
- screenWidthInPoints: 1210
- screenHeightInPoints: 834
- buildBundleId: com.nori.catchwords
- comment: （7 文字。公開しない）

記録を読めませんでした:
- /betaFeedbackCrashSubmissions/ACoGiTwMMRuYJgxJWw2fOnk/crashLog: HTTP 404: { ,
    "title" : "The specified resource does not exist",
    "detail" : "There is no resource of type 'betaCrashLogs' with id 'ACoGiTwMMRuYJgxJWw2fOnk'"
  } ]
}
- relationships: {"links": {"self": "https://api.appstoreconnect.apple.com/v1/betaFeedbackCrashSubmissions/ACoGiTwMMRuYJgxJWw2fOnk/relationships/crashLog", "related": "https://api.appstoreconnect.apple.com/v1/betaFeedbackCrashSubmissions/ACoGiTwMMRuYJgxJWw2fOnk/crashLog"}}

## 4. 2026-10-18T15:23:05.934Z  ビルド a1b43617-39b3-4480-bb23-50532ef67074
- deviceModel: iPad16_3
- deviceFamily: IPAD
- osVersion: 26.6.1
- appPlatform: IOS
- architecture: arm64e
- locale: ja-TW
- appUptimeInMilliseconds: 2000
- diskBytesAvailable: 161663823872
- batteryPercentage: 25
- screenWidthInPoints: 834
- screenHeightInPoints: 1210
- buildBundleId: com.nori.catchwords
- comment: （7 文字。公開しない）

記録を読めませんでした:
- /betaFeedbackCrashSubmissions/ADmK1qvS5gqxC9aF2hNPKQo/crashLog: HTTP 404: { ,
    "title" : "The specified resource does not exist",
    "detail" : "There is no resource of type 'betaCrashLogs' with id 'ADmK1qvS5gqxC9aF2hNPKQo'"
  } ]
}
- relationships: {"links": {"self": "https://api.appstoreconnect.apple.com/v1/betaFeedbackCrashSubmissions/ADmK1qvS5gqxC9aF2hNPKQo/relationships/crashLog", "related": "https://api.appstoreconnect.apple.com/v1/betaFeedbackCrashSubmissions/ADmK1qvS5gqxC9aF2hNPKQo/crashLog"}}

## 5. 2026-10-18T15:17:12.276Z  ビルド a1b43617-39b3-4480-bb23-50532ef67074
- deviceModel: iPad16_3
- deviceFamily: IPAD
- osVersion: 26.6.1
- appPlatform: IOS
- architecture: arm64e
- locale: ja-TW
- appUptimeInMilliseconds: 2000
- diskBytesAvailable: 161675829248
- batteryPercentage: 25
- screenWidthInPoints: 834
- screenHeightInPoints: 1210
- buildBundleId: com.nori.catchwords
- comment: （14 文字。公開しない）

記録を読めませんでした:
- /betaFeedbackCrashSubmissions/ALDb2KOVio3VDEdJT1baIp0/crashLog: HTTP 404: { ,
    "title" : "The specified resource does not exist",
    "detail" : "There is no resource of type 'betaCrashLogs' with id 'ALDb2KOVio3VDEdJT1baIp0'"
  } ]
}
- relationships: {"links": {"self": "https://api.appstoreconnect.apple.com/v1/betaFeedbackCrashSubmissions/ALDb2KOVio3VDEdJT1baIp0/relationships/crashLog", "related": "https://api.appstoreconnect.apple.com/v1/betaFeedbackCrashSubmissions/ALDb2KOVio3VDEdJT1baIp0/crashLog"}}

## 6. 2026-10-18T14:18:53.132Z  ビルド a1b43617-39b3-4480-bb23-50532ef67074
- deviceModel: iPad16_3
- deviceFamily: IPAD
- osVersion: 26.6.1
- appPlatform: IOS
- architecture: arm64e
- locale: ja-TW
- appUptimeInMilliseconds: 3000
- diskBytesAvailable: 161684656128
- batteryPercentage: 30
- screenWidthInPoints: 1210
- screenHeightInPoints: 834
- buildBundleId: com.nori.catchwords
- comment: （16 文字。公開しない）

記録を読めませんでした:
- /betaFeedbackCrashSubmissions/AGAI0EI-8ZjnVxcMVqsaFVo/crashLog: HTTP 404: { ,
    "title" : "The specified resource does not exist",
    "detail" : "There is no resource of type 'betaCrashLogs' with id 'AGAI0EI-8ZjnVxcMVqsaFVo'"
  } ]
}
- relationships: {"links": {"self": "https://api.appstoreconnect.apple.com/v1/betaFeedbackCrashSubmissions/AGAI0EI-8ZjnVxcMVqsaFVo/relationships/crashLog", "related": "https://api.appstoreconnect.apple.com/v1/betaFeedbackCrashSubmissions/AGAI0EI-8ZjnVxcMVqsaFVo/crashLog"}}

