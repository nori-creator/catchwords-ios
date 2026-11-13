# TestFlight に届いたクラッシュ（新しい順）

## 1. 2026-11-08T13:07:48.254Z  ビルド 1.0.5 (1089)
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

## 2. 2026-11-02T08:59:57.243Z  ビルド 1.0.4 (1075)
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

## 3. 2026-10-18T15:23:05.934Z  ビルド a1b43617-39b3-4480-bb23-50532ef67074
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

## 4. 2026-10-18T15:17:12.276Z  ビルド a1b43617-39b3-4480-bb23-50532ef67074
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

## 5. 2026-10-18T14:18:53.132Z  ビルド a1b43617-39b3-4480-bb23-50532ef67074
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

