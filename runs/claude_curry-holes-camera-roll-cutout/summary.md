
| box | runs | failed | rectangle (no cut-out) |
|---|---|---|---|
| tight | 105 | 0 | 10 |
| loose | 80 | 9 | 10 |
| small | 80 | 2 | 13 |
| right | 80 | 7 | 11 |
| left | 80 | 1 | 8 |
| down | 80 | 0 | 8 |
| up | 80 | 0 | 11 |
| point-off | 80 | 0 | 5 |

| case | thing | before (old plan) | after (now) | covers before → after | straight before → after | rectangle | other thing | result |
|---|---|---|---|---|---|---|---|---|
| dorayaki-box-right | 冰淇淋 | CLIP [1] to box (0.18,0.34 0.64×0.34) | part of [1] (40672 px) | 100% → 100% | 0% → 0% | no → no | 0% | ok |
| dorayaki-box-right | 盒子 | CLIP [1] to box (0.17,0.03 0.65×0.34) | part of [1] (45146 px) | 98% → 98% | 28% → 28% | no → no | 0% | ok |
| dorayaki-box-off | 冰淇淋 | instance 1 | instance 1 + region | 100% → 100% | 0% → 0% | no → no | 0% | ok |
| dorayaki-box-off-carton | 冰淇淋 | CLIP [1] to box (0.42,0.33 0.42×0.31) | part of [1] (40614 px) | 65% → 100% | 97% → 0% | no → no | 0% | ok |
| dorayaki-box-off-carton | 盒子 | CLIP [1] to box (0.17,0.03 0.65×0.34) | part of [1] (45146 px) | 98% → 98% | 28% → 28% | no → no | 0% | ok |
| dorayaki-box-30-smaller | 冰淇淋 | instance 1 | instance 1 + region | 100% → 100% | 0% → 0% | no → no | 0% | ok |
| dorayaki-no-box | 冰淇淋 | instance 1 | instance 1 | 100% → 100% | 0% → 0% | no → no | 0% | ok |
| dorayaki-point-outside | 冰淇淋 | instance 1 | instance 1 + region | 100% → 100% | 0% → 0% | no → no | 0% | ok |
| dorayaki-exif-rotated | 冰淇淋 | instance 1 | instance 1 + region | 100% → 100% | 0% → 0% | no → no | 0% | ok |
| coffee-cup-saucer-spoon | 杯子 | CLIP [1] to box (0.27,0.01 0.40×0.80) | part of [1] (123888 px) | 98% → 98% | 9% → 9% | no → no | 5% | ok |
| coffee-cup-saucer-spoon | 盤子 | instance 1 | part of [1] (86886 px) | - → - | - → - | - → - | - | ok |
| coffee-cup-saucer-spoon | 湯匙 | CLIP [1] to box (0.53,0.14 0.17×0.70) | part of [1] (123721 px), no cut-out | 100% → 0% | 0% → 0% | no → no | 0% | ok |
| coffee-cup-box-small | 杯子 | instance 1 | instance 1 + region | 98% → 98% | 9% → 9% | no → no | 0% | ok |
| chelsea-fills-frame | 貓 | instance 1 | instance 1 | 99% → 99% | 30% → 30% | no → no | 0% | ok |
| chelsea-box-small | 貓 | instance 1 | instance 1 | 99% → 99% | 30% → 30% | no → no | 0% | ok |
| astronaut-helmet | 安全帽 | CLIP [1] to box (0.52,0.66 0.48×0.34) | part of [1] (43040 px) | 100% → 100% | 2% → 2% | no → no | 0% | ok |
| astronaut-helmet | 太空梭 | no mask | no mask, no cut-out (expected: none — Vision has no instance for the model shuttle in the whole photo, and the crop round its box has only one instance, lying mostly outside the box; the old plan cut that crop instance at the crop's edge (a straight cut along 100% of a line). No cut-out is the honest result.) | 97% → 0% | 100% → 0% | no → no | 0% | ok |
| astronaut-helmet | 太空人 | CLIP [1] to box (0.00,0.00 0.75×1.00) | part of [1] (137242 px), no cut-out | - → - | - → - | - → - | - | ok |
| cafe-cup-vase | 咖啡 | instance 1 | instance 1 | 100% → 100% | 0% → 1% | no → no | 0% | ok |
| cafe-cup-vase | 花瓶 | no mask | no mask | 98% → 97% | 20% → 20% | no → no | 0% | ok |
| cafe-cup-vase | 花 | no mask | no mask, no cut-out | - → - | - → - | - → - | - | ok |
| cat-and-plant | 貓 | instance 1 | instance 1 | 95% → 95% | 27% → 29% | no → no | 0% | ok |
| cat-and-plant | 植物 | no mask | no mask, no cut-out | - → - | - → - | - → - | - | ok |
| boba-portrait | 珍珠奶茶 | instance 1 | instance 1 | 96% → 96% | 25% → 28% | no → no | 0% | ok |
| glasses-against-bottle | 眼鏡 | CLIP [1] to box (0.16,0.53 0.63×0.30) | part of [1] (5554 px) | 100% → 100% | 0% → 0% | no → no | 0% | ok |
| glasses-against-bottle | 水壺 | CLIP [1] to box (0.62,0.09 0.29×0.78) | part of [1] (23656 px) | 100% → 100% | 0% → 0% | no → no | 0% | ok |
| keys-on-remote | 遙控器 | instance 1 | instance 1 | 100% → 100% | 0% → 0% | no → no | 0% | ok |
| keys-on-remote | 鑰匙 | instance 2 | instance 2 | 100% → 100% | 0% → 1% | no → no | 0% | ok |
| lint-roller | 滾筒黏毛器 | instance 2 | union [1, 2] | 30% → 99% | 2% → 7% | no → no | 0% | ok |
| lint-roller-loose-box | 滾筒黏毛器 | instance 2 | union [1, 2] | 30% → 99% | 2% → 7% | no → no | 0% | ok |
| lint-roller-roller-named | 滾筒黏毛器 | instance 2 | union [1, 2] | 30% → 99% | 2% → 7% | no → no | 0% | ok |
| lint-roller-roller-named | 黏毛紙 | instance 1 | instance 1 | - → - | - → - | - → - | - | ok |
| stool-on-floor/tight | 塑膠椅 | instance 1 | instance 1 | 100% → 100% | 2% → 2% | no → no | 0% | ok |
| stool-on-floor/loose | 塑膠椅 | instance 1 | instance 1 | 100% → 100% | 2% → 2% | no → no | 0% | ok |
| stool-on-floor/small | 塑膠椅 | instance 1 | instance 1 | 100% → 100% | 2% → 2% | no → no | 0% | ok |
| stool-on-floor/right | 塑膠椅 | instance 1 | instance 1 | 100% → 100% | 2% → 2% | no → no | 0% | ok |
| stool-on-floor/left | 塑膠椅 | instance 1 | instance 1 | 100% → 100% | 2% → 2% | no → no | 0% | ok |
| stool-on-floor/down | 塑膠椅 | instance 1 | instance 1 | 100% → 100% | 2% → 2% | no → no | 0% | ok |
| stool-on-floor/up | 塑膠椅 | instance 1 | instance 1 | 100% → 100% | 2% → 2% | no → no | 0% | ok |
| stool-on-floor/point-off | 塑膠椅 | instance 1 | instance 1 | 100% → 100% | 2% → 2% | no → no | 0% | ok |
| keys-on-floor/tight | 鑰匙 | instance 1 | instance 1 | 100% → 100% | 3% → 1% | no → no | 0% | ok |
| keys-on-floor/loose | 鑰匙 | instance 1 | instance 1 | 100% → 100% | 3% → 1% | no → no | 0% | ok |
| keys-on-floor/small | 鑰匙 | instance 1 | instance 1 | 100% → 100% | 3% → 1% | no → no | 0% | ok |
| keys-on-floor/right | 鑰匙 | instance 1 | instance 1 | 100% → 100% | 3% → 1% | no → no | 0% | ok |
| keys-on-floor/left | 鑰匙 | instance 1 | instance 1 | 100% → 100% | 3% → 1% | no → no | 0% | ok |
| keys-on-floor/down | 鑰匙 | instance 1 | instance 1 | 100% → 100% | 3% → 1% | no → no | 0% | ok |
| keys-on-floor/up | 鑰匙 | instance 1 | instance 1 | 100% → 100% | 3% → 1% | no → no | 0% | ok |
| keys-on-floor/point-off | 鑰匙 | instance 1 | instance 1 | 100% → 100% | 3% → 1% | no → no | 0% | ok |
| umbrella-on-floor/tight | 雨傘 | instance 1 | instance 1 | 100% → 100% | 0% → 6% | no → no | 0% | ok |
| umbrella-on-floor/loose | 雨傘 | instance 1 | instance 1 | 100% → 100% | 0% → 6% | no → no | 0% | ok |
| umbrella-on-floor/small | 雨傘 | instance 1 | instance 1 | 100% → 100% | 0% → 6% | no → no | 0% | ok |
| umbrella-on-floor/right | 雨傘 | instance 1 | instance 1 | 100% → 100% | 0% → 6% | no → no | 0% | ok |
| umbrella-on-floor/left | 雨傘 | instance 1 | instance 1 | 100% → 100% | 0% → 6% | no → no | 0% | ok |
| umbrella-on-floor/down | 雨傘 | instance 1 | instance 1 | 100% → 100% | 0% → 6% | no → no | 0% | ok |
| umbrella-on-floor/up | 雨傘 | instance 1 | instance 1 | 100% → 100% | 0% → 6% | no → no | 0% | ok |
| umbrella-on-floor/point-off | 雨傘 | instance 1 | instance 1 | 100% → 100% | 0% → 6% | no → no | 0% | ok |
| slippers-on-floor/tight | 拖鞋 | instance 2 | union [1, 2] | 50% → 100% | 0% → 0% | no → no | 0% | ok |
| slippers-on-floor/loose | 拖鞋 | instance 1 | union [1, 2] | 50% → 100% | 0% → 0% | no → no | 0% | ok |
| slippers-on-floor/small | 拖鞋 | instance 1 | union [1, 2] | 50% → 100% | 0% → 0% | no → no | 0% | ok |
| slippers-on-floor/right | 拖鞋 | instance 1 | union [1, 2] | 50% → 100% | 0% → 0% | no → no | 0% | ok |
| slippers-on-floor/left | 拖鞋 | instance 2 | union [1, 2] | 50% → 100% | 0% → 0% | no → no | 0% | ok |
| slippers-on-floor/down | 拖鞋 | instance 2 | union [1, 2] | 50% → 100% | 0% → 0% | no → no | 0% | ok |
| slippers-on-floor/up | 拖鞋 | instance 1 | union [1, 2] | 50% → 100% | 0% → 0% | no → no | 0% | ok |
| slippers-on-floor/point-off | 拖鞋 | instance 2 | union [1, 2] | 50% → 100% | 0% → 0% | no → no | 0% | ok |
| lantern-on-floor/tight | 燈籠 | instance 1 | instance 1 | 100% → 100% | 0% → 0% | no → no | 0% | ok |
| lantern-on-floor/loose | 燈籠 | instance 1 | instance 1 | 100% → 100% | 0% → 0% | no → no | 0% | ok |
| lantern-on-floor/small | 燈籠 | instance 1 | instance 1 | 100% → 100% | 0% → 0% | no → no | 0% | ok |
| lantern-on-floor/right | 燈籠 | instance 1 | instance 1 | 100% → 100% | 0% → 0% | no → no | 0% | ok |
| lantern-on-floor/left | 燈籠 | instance 1 | instance 1 | 100% → 100% | 0% → 0% | no → no | 0% | ok |
| lantern-on-floor/down | 燈籠 | instance 1 | instance 1 | 100% → 100% | 0% → 0% | no → no | 0% | ok |
| lantern-on-floor/up | 燈籠 | instance 1 | instance 1 | 100% → 100% | 0% → 0% | no → no | 0% | ok |
| lantern-on-floor/point-off | 燈籠 | instance 1 | instance 1 | 100% → 100% | 0% → 0% | no → no | 0% | ok |
| banana-on-floor/tight | 香蕉 | instance 1 | instance 1 | 100% → 100% | 0% → 0% | no → no | 0% | ok |
| banana-on-floor/loose | 香蕉 | instance 1 | instance 1 | 100% → 100% | 0% → 0% | no → no | 0% | ok |
| banana-on-floor/small | 香蕉 | instance 1 | instance 1 | 100% → 100% | 0% → 0% | no → no | 0% | ok |
| banana-on-floor/right | 香蕉 | instance 1 | instance 1 | 100% → 100% | 0% → 0% | no → no | 0% | ok |
| banana-on-floor/left | 香蕉 | instance 1 | instance 1 | 100% → 100% | 0% → 0% | no → no | 0% | ok |
| banana-on-floor/down | 香蕉 | instance 1 | instance 1 | 100% → 100% | 0% → 0% | no → no | 0% | ok |
| banana-on-floor/up | 香蕉 | instance 1 | instance 1 | 100% → 100% | 0% → 0% | no → no | 0% | ok |
| banana-on-floor/point-off | 香蕉 | instance 1 | instance 1 | 100% → 100% | 0% → 0% | no → no | 0% | ok |
| bubble-tea-cup-on-floor/tight | 珍珠奶茶 | instance 1 | instance 1 | 100% → 100% | 0% → 0% | no → no | 0% | ok |
| bubble-tea-cup-on-floor/loose | 珍珠奶茶 | instance 1 | instance 1 | 100% → 100% | 0% → 0% | no → no | 0% | ok |
| bubble-tea-cup-on-floor/small | 珍珠奶茶 | instance 1 | instance 1 | 100% → 100% | 0% → 0% | no → no | 0% | ok |
| bubble-tea-cup-on-floor/right | 珍珠奶茶 | instance 1 | instance 1 | 100% → 100% | 0% → 0% | no → no | 0% | ok |
| bubble-tea-cup-on-floor/left | 珍珠奶茶 | instance 1 | instance 1 | 100% → 100% | 0% → 0% | no → no | 0% | ok |
| bubble-tea-cup-on-floor/down | 珍珠奶茶 | instance 1 | instance 1 | 100% → 100% | 0% → 0% | no → no | 0% | ok |
| bubble-tea-cup-on-floor/up | 珍珠奶茶 | instance 1 | instance 1 | 100% → 100% | 0% → 0% | no → no | 0% | ok |
| bubble-tea-cup-on-floor/point-off | 珍珠奶茶 | instance 1 | instance 1 | 100% → 100% | 0% → 0% | no → no | 0% | ok |
| succulent-on-floor/tight | 多肉植物 | instance 1 | instance 1 | 100% → 100% | 1% → 0% | no → no | 0% | ok |
| succulent-on-floor/loose | 多肉植物 | instance 1 | instance 1 | 100% → 100% | 1% → 0% | no → no | 0% | ok |
| succulent-on-floor/small | 多肉植物 | instance 1 | instance 1 | 100% → 100% | 1% → 0% | no → no | 0% | ok |
| succulent-on-floor/right | 多肉植物 | instance 1 | instance 1 | 100% → 100% | 1% → 0% | no → no | 0% | ok |
| succulent-on-floor/left | 多肉植物 | instance 1 | instance 1 | 100% → 100% | 1% → 0% | no → no | 0% | ok |
| succulent-on-floor/down | 多肉植物 | instance 1 | instance 1 | 100% → 100% | 1% → 0% | no → no | 0% | ok |
| succulent-on-floor/up | 多肉植物 | instance 1 | instance 1 | 100% → 100% | 1% → 0% | no → no | 0% | ok |
| succulent-on-floor/point-off | 多肉植物 | instance 1 | instance 1 | 100% → 100% | 1% → 0% | no → no | 0% | ok |
| cola-on-floor/tight | 可樂 | instance 1 | instance 1 | 100% → 100% | 0% → 0% | no → no | 0% | ok |
| cola-on-floor/loose | 可樂 | instance 1 | instance 1 | 100% → 100% | 0% → 0% | no → no | 0% | ok |
| cola-on-floor/small | 可樂 | instance 1 | instance 1 | 100% → 100% | 0% → 0% | no → no | 0% | ok |
| cola-on-floor/right | 可樂 | instance 1 | instance 1 | 100% → 100% | 0% → 0% | no → no | 0% | ok |
| cola-on-floor/left | 可樂 | instance 1 | instance 1 | 100% → 100% | 0% → 0% | no → no | 0% | ok |
| cola-on-floor/down | 可樂 | instance 1 | instance 1 | 100% → 100% | 0% → 0% | no → no | 0% | ok |
| cola-on-floor/up | 可樂 | instance 1 | instance 1 | 100% → 100% | 0% → 0% | no → no | 0% | ok |
| cola-on-floor/point-off | 可樂 | instance 1 | instance 1 | 100% → 100% | 0% → 0% | no → no | 0% | ok |
| juice-on-floor/tight | 果汁 | instance 1 | instance 1 | 100% → 100% | 0% → 0% | no → no | 0% | ok |
| juice-on-floor/loose | 果汁 | instance 1 | instance 1 | 100% → 100% | 0% → 0% | no → no | 0% | ok |
| juice-on-floor/small | 果汁 | instance 1 | instance 1 | 100% → 100% | 0% → 0% | no → no | 0% | ok |
| juice-on-floor/right | 果汁 | instance 1 | instance 1 | 100% → 100% | 0% → 0% | no → no | 0% | ok |
| juice-on-floor/left | 果汁 | instance 1 | instance 1 | 100% → 100% | 0% → 0% | no → no | 0% | ok |
| juice-on-floor/down | 果汁 | instance 1 | instance 1 | 100% → 100% | 0% → 0% | no → no | 0% | ok |
| juice-on-floor/up | 果汁 | instance 1 | instance 1 | 100% → 100% | 0% → 0% | no → no | 0% | ok |
| juice-on-floor/point-off | 果汁 | instance 1 | instance 1 | 100% → 100% | 0% → 0% | no → no | 0% | ok |
| oolong-on-floor/tight | 烏龍茶 | instance 1 | instance 1 | 100% → 100% | 0% → 14% | no → no | 0% | ok |
| oolong-on-floor/loose | 烏龍茶 | instance 1 | instance 1 | 100% → 100% | 0% → 14% | no → no | 0% | ok |
| oolong-on-floor/small | 烏龍茶 | instance 1 | instance 1 | 100% → 100% | 0% → 14% | no → no | 0% | ok |
| oolong-on-floor/right | 烏龍茶 | instance 1 | instance 1 | 100% → 100% | 0% → 14% | no → no | 0% | ok |
| oolong-on-floor/left | 烏龍茶 | instance 1 | instance 1 | 100% → 100% | 0% → 14% | no → no | 0% | ok |
| oolong-on-floor/down | 烏龍茶 | instance 1 | instance 1 | 100% → 100% | 0% → 14% | no → no | 0% | ok |
| oolong-on-floor/up | 烏龍茶 | instance 1 | instance 1 | 100% → 100% | 0% → 14% | no → no | 0% | ok |
| oolong-on-floor/point-off | 烏龍茶 | instance 1 | instance 1 | 100% → 100% | 0% → 14% | no → no | 0% | ok |
| mango-on-floor/tight | 芒果 | instance 1 | instance 1 | 100% → 100% | 0% → 0% | no → no | 0% | ok |
| mango-on-floor/loose | 芒果 | instance 1 | instance 1 | 100% → 100% | 0% → 0% | no → no | 0% | ok |
| mango-on-floor/small | 芒果 | instance 1 | instance 1 | 100% → 100% | 0% → 0% | no → no | 0% | ok |
| mango-on-floor/right | 芒果 | instance 1 | instance 1 | 100% → 100% | 0% → 0% | no → no | 0% | ok |
| mango-on-floor/left | 芒果 | instance 1 | instance 1 | 100% → 100% | 0% → 0% | no → no | 0% | ok |
| mango-on-floor/down | 芒果 | instance 1 | instance 1 | 100% → 100% | 0% → 0% | no → no | 0% | ok |
| mango-on-floor/up | 芒果 | instance 1 | instance 1 | 100% → 100% | 0% → 0% | no → no | 0% | ok |
| mango-on-floor/point-off | 芒果 | instance 1 | instance 1 | 100% → 100% | 0% → 0% | no → no | 0% | ok |
| pineapple-cake-on-floor/tight | 鳳梨酥 | instance 1 | instance 1 | 100% → 100% | 0% → 0% | no → no | 0% | ok |
| pineapple-cake-on-floor/loose | 鳳梨酥 | instance 1 | instance 1 | 100% → 100% | 0% → 0% | no → no | 0% | ok |
| pineapple-cake-on-floor/small | 鳳梨酥 | instance 1 | instance 1 | 100% → 100% | 0% → 0% | no → no | 0% | ok |
| pineapple-cake-on-floor/right | 鳳梨酥 | instance 1 | instance 1 | 100% → 100% | 0% → 0% | no → no | 0% | ok |
| pineapple-cake-on-floor/left | 鳳梨酥 | instance 1 | instance 1 | 100% → 100% | 0% → 0% | no → no | 0% | ok |
| pineapple-cake-on-floor/down | 鳳梨酥 | instance 1 | instance 1 | 100% → 100% | 0% → 0% | no → no | 0% | ok |
| pineapple-cake-on-floor/up | 鳳梨酥 | instance 1 | instance 1 | 100% → 100% | 0% → 0% | no → no | 0% | ok |
| pineapple-cake-on-floor/point-off | 鳳梨酥 | instance 1 | instance 1 | 100% → 100% | 0% → 0% | no → no | 0% | ok |
| xiaolongbao-on-floor/tight | 小籠包 | instance 1 | instance 1 | 100% → 100% | 0% → 0% | no → no | 0% | ok |
| xiaolongbao-on-floor/loose | 小籠包 | instance 1 | instance 1 | 100% → 100% | 0% → 0% | no → no | 0% | ok |
| xiaolongbao-on-floor/small | 小籠包 | instance 1 | instance 1 | 100% → 100% | 0% → 0% | no → no | 0% | ok |
| xiaolongbao-on-floor/right | 小籠包 | instance 1 | instance 1 | 100% → 100% | 0% → 0% | no → no | 0% | ok |
| xiaolongbao-on-floor/left | 小籠包 | instance 1 | instance 1 | 100% → 100% | 0% → 0% | no → no | 0% | ok |
| xiaolongbao-on-floor/down | 小籠包 | instance 1 | instance 1 | 100% → 100% | 0% → 0% | no → no | 0% | ok |
| xiaolongbao-on-floor/up | 小籠包 | instance 1 | instance 1 | 100% → 100% | 0% → 0% | no → no | 0% | ok |
| xiaolongbao-on-floor/point-off | 小籠包 | instance 1 | instance 1 | 100% → 100% | 0% → 0% | no → no | 0% | ok |
| pomelo-on-floor/tight | 柚子 | instance 1 | instance 1 | 100% → 100% | 0% → 0% | no → no | 0% | ok |
| pomelo-on-floor/loose | 柚子 | instance 1 | instance 1 | 100% → 100% | 0% → 0% | no → no | 0% | ok |
| pomelo-on-floor/small | 柚子 | instance 1 | instance 1 | 100% → 100% | 0% → 0% | no → no | 0% | ok |
| pomelo-on-floor/right | 柚子 | instance 1 | instance 1 | 100% → 100% | 0% → 0% | no → no | 0% | ok |
| pomelo-on-floor/left | 柚子 | instance 1 | instance 1 | 100% → 100% | 0% → 0% | no → no | 0% | ok |
| pomelo-on-floor/down | 柚子 | instance 1 | instance 1 | 100% → 100% | 0% → 0% | no → no | 0% | ok |
| pomelo-on-floor/up | 柚子 | instance 1 | instance 1 | 100% → 100% | 0% → 0% | no → no | 0% | ok |
| pomelo-on-floor/point-off | 柚子 | instance 1 | instance 1 | 100% → 100% | 0% → 0% | no → no | 0% | ok |
| lint-roller-on-floor/tight | 滾筒黏毛器 | instance 2 | union [1, 2] | 28% → 100% | 3% → 0% | no → no | 0% | ok |
| lint-roller-on-floor/loose | 滾筒黏毛器 | instance 2 | union [1, 2] | 28% → 100% | 3% → 0% | no → no | 0% | ok |
| lint-roller-on-floor/small | 滾筒黏毛器 | instance 2 | union [1, 2] + region | 28% → 100% | 3% → 1% | no → no | 0% | ok |
| lint-roller-on-floor/right | 滾筒黏毛器 | instance 2 | union [1, 2] | 28% → 100% | 3% → 0% | no → no | 0% | ok |
| lint-roller-on-floor/left | 滾筒黏毛器 | instance 2 | union [1, 2] | 28% → 100% | 3% → 0% | no → no | 0% | ok |
| lint-roller-on-floor/down | 滾筒黏毛器 | instance 2 | union [1, 2] | 28% → 100% | 3% → 0% | no → no | 0% | ok |
| lint-roller-on-floor/up | 滾筒黏毛器 | instance 2 | union [1, 2] | 28% → 100% | 3% → 0% | no → no | 0% | ok |
| lint-roller-on-floor/point-off | 滾筒黏毛器 | instance 2 | union [1, 2] | 28% → 100% | 3% → 0% | no → no | 0% | ok |
| stool-on-cafe/tight | 塑膠椅 | instance 1 | instance 1 | 100% → 100% | 0% → 0% | no → no | 0% | ok |
| stool-on-cafe/loose | 塑膠椅 | instance 1 | instance 1 | 100% → 100% | 0% → 0% | no → no | 0% | ok |
| stool-on-cafe/small | 塑膠椅 | instance 1 | instance 1 | 100% → 100% | 0% → 0% | no → no | 0% | ok |
| stool-on-cafe/right | 塑膠椅 | instance 1 | instance 1 | 100% → 100% | 0% → 0% | no → no | 0% | ok |
| stool-on-cafe/left | 塑膠椅 | instance 1 | instance 1 | 100% → 100% | 0% → 0% | no → no | 0% | ok |
| stool-on-cafe/down | 塑膠椅 | instance 1 | instance 1 | 100% → 100% | 0% → 0% | no → no | 0% | ok |
| stool-on-cafe/up | 塑膠椅 | instance 1 | instance 1 | 100% → 100% | 0% → 0% | no → no | 0% | ok |
| stool-on-cafe/point-off | 塑膠椅 | instance 1 | instance 1 | 100% → 100% | 0% → 0% | no → no | 0% | ok |
| keys-on-cafe/tight | 鑰匙 | instance 1 | instance 1 | 100% → 100% | 0% → 0% | no → no | 0% | ok |
| keys-on-cafe/loose | 鑰匙 | instance 1 | instance 1 | 100% → 100% | 0% → 0% | no → no | 0% | ok |
| keys-on-cafe/small | 鑰匙 | instance 1 | instance 1 | 100% → 100% | 0% → 0% | no → no | 0% | ok |
| keys-on-cafe/right | 鑰匙 | instance 1 | instance 1 | 100% → 100% | 0% → 0% | no → no | 0% | ok |
| keys-on-cafe/left | 鑰匙 | instance 1 | instance 1 | 100% → 100% | 0% → 0% | no → no | 0% | ok |
| keys-on-cafe/down | 鑰匙 | instance 1 | instance 1 | 100% → 100% | 0% → 0% | no → no | 0% | ok |
| keys-on-cafe/up | 鑰匙 | instance 1 | instance 1 | 100% → 100% | 0% → 0% | no → no | 0% | ok |
| keys-on-cafe/point-off | 鑰匙 | instance 1 | instance 1 | 100% → 100% | 0% → 0% | no → no | 0% | ok |
| umbrella-on-cafe/tight | 雨傘 | instance 1 | instance 1 | 100% → 100% | 0% → 0% | no → no | 0% | ok |
| umbrella-on-cafe/loose | 雨傘 | instance 1 | instance 1 | 100% → 100% | 0% → 0% | no → no | 0% | ok |
| umbrella-on-cafe/small | 雨傘 | instance 1 | instance 1 + region | 100% → 100% | 0% → 5% | no → no | 0% | ok |
| umbrella-on-cafe/right | 雨傘 | instance 1 | instance 1 | 100% → 100% | 0% → 0% | no → no | 0% | ok |
| umbrella-on-cafe/left | 雨傘 | instance 1 | instance 1 | 100% → 100% | 0% → 0% | no → no | 0% | ok |
| umbrella-on-cafe/down | 雨傘 | instance 1 | instance 1 | 100% → 100% | 0% → 0% | no → no | 0% | ok |
| umbrella-on-cafe/up | 雨傘 | instance 1 | instance 1 | 100% → 100% | 0% → 0% | no → no | 0% | ok |
| umbrella-on-cafe/point-off | 雨傘 | instance 1 | instance 1 | 100% → 100% | 0% → 0% | no → no | 0% | ok |
| slippers-on-cafe/tight | 拖鞋 | instance 1 | union [1, 2] | 50% → 100% | 0% → 0% | no → no | 0% | ok |
| slippers-on-cafe/loose | 拖鞋 | instance 1 | union [1, 2] | 50% → 100% | 0% → 0% | no → no | 0% | ok |
| slippers-on-cafe/small | 拖鞋 | instance 1 | union [1, 2] | 50% → 100% | 0% → 0% | no → no | 0% | ok |
| slippers-on-cafe/right | 拖鞋 | instance 1 | union [1, 2] | 50% → 100% | 0% → 0% | no → no | 0% | ok |
| slippers-on-cafe/left | 拖鞋 | instance 2 | union [1, 2] | 50% → 100% | 0% → 0% | no → no | 0% | ok |
| slippers-on-cafe/down | 拖鞋 | instance 1 | union [1, 2] | 50% → 100% | 0% → 0% | no → no | 0% | ok |
| slippers-on-cafe/up | 拖鞋 | instance 1 | union [1, 2] | 50% → 100% | 0% → 0% | no → no | 0% | ok |
| slippers-on-cafe/point-off | 拖鞋 | instance 2 | union [1, 2] | 50% → 100% | 0% → 0% | no → no | 0% | ok |
| lantern-on-cafe/tight | 燈籠 | instance 1 | instance 1 | 100% → 100% | 0% → 0% | no → no | 0% | ok |
| lantern-on-cafe/loose | 燈籠 | instance 1 | instance 1 | 100% → 100% | 0% → 0% | no → no | 0% | ok |
| lantern-on-cafe/small | 燈籠 | instance 1 | instance 1 | 100% → 100% | 0% → 0% | no → no | 0% | ok |
| lantern-on-cafe/right | 燈籠 | instance 1 | instance 1 | 100% → 100% | 0% → 0% | no → no | 0% | ok |
| lantern-on-cafe/left | 燈籠 | instance 1 | instance 1 | 100% → 100% | 0% → 0% | no → no | 0% | ok |
| lantern-on-cafe/down | 燈籠 | instance 1 | instance 1 | 100% → 100% | 0% → 0% | no → no | 0% | ok |
| lantern-on-cafe/up | 燈籠 | instance 1 | instance 1 | 100% → 100% | 0% → 0% | no → no | 0% | ok |
| lantern-on-cafe/point-off | 燈籠 | instance 1 | instance 1 | 100% → 100% | 0% → 0% | no → no | 0% | ok |
| banana-on-cafe/tight | 香蕉 | instance 1 | instance 1 | 100% → 100% | 0% → 0% | no → no | 0% | ok |
| banana-on-cafe/loose | 香蕉 | instance 1 | instance 1 | 100% → 100% | 0% → 0% | no → no | 0% | ok |
| banana-on-cafe/small | 香蕉 | instance 1 | instance 1 | 100% → 100% | 0% → 0% | no → no | 0% | ok |
| banana-on-cafe/right | 香蕉 | instance 1 | instance 1 | 100% → 100% | 0% → 0% | no → no | 0% | ok |
| banana-on-cafe/left | 香蕉 | instance 1 | instance 1 | 100% → 100% | 0% → 0% | no → no | 0% | ok |
| banana-on-cafe/down | 香蕉 | instance 1 | instance 1 | 100% → 100% | 0% → 0% | no → no | 0% | ok |
| banana-on-cafe/up | 香蕉 | instance 1 | instance 1 | 100% → 100% | 0% → 0% | no → no | 0% | ok |
| banana-on-cafe/point-off | 香蕉 | instance 1 | instance 1 | 100% → 100% | 0% → 0% | no → no | 0% | ok |
| bubble-tea-cup-on-cafe/tight | 珍珠奶茶 | instance 1 | instance 1 | 100% → 100% | 0% → 0% | no → no | 0% | ok |
| bubble-tea-cup-on-cafe/loose | 珍珠奶茶 | instance 1 | instance 1 | 100% → 100% | 0% → 0% | no → no | 0% | ok |
| bubble-tea-cup-on-cafe/small | 珍珠奶茶 | instance 1 | instance 1 | 100% → 100% | 0% → 0% | no → no | 0% | ok |
| bubble-tea-cup-on-cafe/right | 珍珠奶茶 | instance 1 | instance 1 | 100% → 100% | 0% → 0% | no → no | 0% | ok |
| bubble-tea-cup-on-cafe/left | 珍珠奶茶 | instance 1 | instance 1 | 100% → 100% | 0% → 0% | no → no | 0% | ok |
| bubble-tea-cup-on-cafe/down | 珍珠奶茶 | instance 1 | instance 1 | 100% → 100% | 0% → 0% | no → no | 0% | ok |
| bubble-tea-cup-on-cafe/up | 珍珠奶茶 | instance 1 | instance 1 | 100% → 100% | 0% → 0% | no → no | 0% | ok |
| bubble-tea-cup-on-cafe/point-off | 珍珠奶茶 | instance 1 | instance 1 | 100% → 100% | 0% → 0% | no → no | 0% | ok |
| succulent-on-cafe/tight | 多肉植物 | instance 1 | instance 1 | 100% → 100% | 0% → 0% | no → no | 0% | ok |
| succulent-on-cafe/loose | 多肉植物 | instance 1 | instance 1 | 100% → 100% | 0% → 0% | no → no | 0% | ok |
| succulent-on-cafe/small | 多肉植物 | instance 1 | instance 1 + region | 100% → 100% | 0% → 0% | no → no | 0% | ok |
| succulent-on-cafe/right | 多肉植物 | instance 1 | instance 1 | 100% → 100% | 0% → 0% | no → no | 0% | ok |
| succulent-on-cafe/left | 多肉植物 | instance 1 | instance 1 | 100% → 100% | 0% → 0% | no → no | 0% | ok |
| succulent-on-cafe/down | 多肉植物 | instance 1 | instance 1 | 100% → 100% | 0% → 0% | no → no | 0% | ok |
| succulent-on-cafe/up | 多肉植物 | instance 1 | instance 1 | 100% → 100% | 0% → 0% | no → no | 0% | ok |
| succulent-on-cafe/point-off | 多肉植物 | instance 1 | instance 1 | 100% → 100% | 0% → 0% | no → no | 0% | ok |
| cola-on-cafe/tight | 可樂 | instance 1 | instance 1 | 100% → 100% | 0% → 0% | no → no | 0% | ok |
| cola-on-cafe/loose | 可樂 | instance 1 | instance 1 | 100% → 100% | 0% → 0% | no → no | 0% | ok |
| cola-on-cafe/small | 可樂 | instance 1 | instance 1 | 100% → 100% | 0% → 0% | no → no | 0% | ok |
| cola-on-cafe/right | 可樂 | instance 1 | instance 1 | 100% → 100% | 0% → 0% | no → no | 0% | ok |
| cola-on-cafe/left | 可樂 | instance 1 | instance 1 | 100% → 100% | 0% → 0% | no → no | 0% | ok |
| cola-on-cafe/down | 可樂 | instance 1 | instance 1 | 100% → 100% | 0% → 0% | no → no | 0% | ok |
| cola-on-cafe/up | 可樂 | instance 1 | instance 1 | 100% → 100% | 0% → 0% | no → no | 0% | ok |
| cola-on-cafe/point-off | 可樂 | instance 1 | instance 1 | 100% → 100% | 0% → 0% | no → no | 0% | ok |
| juice-on-cafe/tight | 果汁 | instance 1 | instance 1 | 100% → 100% | 0% → 0% | no → no | 0% | ok |
| juice-on-cafe/loose | 果汁 | instance 1 | instance 1 | 100% → 100% | 0% → 0% | no → no | 0% | ok |
| juice-on-cafe/small | 果汁 | instance 1 | instance 1 | 100% → 100% | 0% → 0% | no → no | 0% | ok |
| juice-on-cafe/right | 果汁 | instance 1 | instance 1 | 100% → 100% | 0% → 0% | no → no | 0% | ok |
| juice-on-cafe/left | 果汁 | instance 1 | instance 1 | 100% → 100% | 0% → 0% | no → no | 0% | ok |
| juice-on-cafe/down | 果汁 | instance 1 | instance 1 | 100% → 100% | 0% → 0% | no → no | 0% | ok |
| juice-on-cafe/up | 果汁 | instance 1 | instance 1 | 100% → 100% | 0% → 0% | no → no | 0% | ok |
| juice-on-cafe/point-off | 果汁 | instance 1 | instance 1 | 100% → 100% | 0% → 0% | no → no | 0% | ok |
| oolong-on-cafe/tight | 烏龍茶 | instance 1 | instance 1 | 100% → 100% | 0% → 0% | no → no | 0% | ok |
| oolong-on-cafe/loose | 烏龍茶 | instance 1 | instance 1 | 100% → 100% | 0% → 0% | no → no | 0% | ok |
| oolong-on-cafe/small | 烏龍茶 | instance 1 | instance 1 | 100% → 100% | 0% → 0% | no → no | 0% | ok |
| oolong-on-cafe/right | 烏龍茶 | instance 1 | instance 1 | 100% → 100% | 0% → 0% | no → no | 0% | ok |
| oolong-on-cafe/left | 烏龍茶 | instance 1 | instance 1 | 100% → 100% | 0% → 0% | no → no | 0% | ok |
| oolong-on-cafe/down | 烏龍茶 | instance 1 | instance 1 | 100% → 100% | 0% → 0% | no → no | 0% | ok |
| oolong-on-cafe/up | 烏龍茶 | instance 1 | instance 1 | 100% → 100% | 0% → 0% | no → no | 0% | ok |
| oolong-on-cafe/point-off | 烏龍茶 | instance 1 | instance 1 | 100% → 100% | 0% → 0% | no → no | 0% | ok |
| mango-on-cafe/tight | 芒果 | instance 1 | instance 1 | 100% → 100% | 0% → 0% | no → no | 0% | ok |
| mango-on-cafe/loose | 芒果 | instance 1 | instance 1 | 100% → 100% | 0% → 0% | no → no | 0% | ok |
| mango-on-cafe/small | 芒果 | instance 1 | instance 1 | 100% → 100% | 0% → 0% | no → no | 0% | ok |
| mango-on-cafe/right | 芒果 | instance 1 | instance 1 | 100% → 100% | 0% → 0% | no → no | 0% | ok |
| mango-on-cafe/left | 芒果 | instance 1 | instance 1 | 100% → 100% | 0% → 0% | no → no | 0% | ok |
| mango-on-cafe/down | 芒果 | instance 1 | instance 1 | 100% → 100% | 0% → 0% | no → no | 0% | ok |
| mango-on-cafe/up | 芒果 | instance 1 | instance 1 | 100% → 100% | 0% → 0% | no → no | 0% | ok |
| mango-on-cafe/point-off | 芒果 | instance 1 | instance 1 | 100% → 100% | 0% → 0% | no → no | 0% | ok |
| pineapple-cake-on-cafe/tight | 鳳梨酥 | instance 1 | instance 1 | 100% → 100% | 0% → 0% | no → no | 0% | ok |
| pineapple-cake-on-cafe/loose | 鳳梨酥 | instance 1 | instance 1 | 100% → 100% | 0% → 0% | no → no | 0% | ok |
| pineapple-cake-on-cafe/small | 鳳梨酥 | instance 1 | instance 1 | 100% → 100% | 0% → 0% | no → no | 0% | ok |
| pineapple-cake-on-cafe/right | 鳳梨酥 | instance 1 | instance 1 | 100% → 100% | 0% → 0% | no → no | 0% | ok |
| pineapple-cake-on-cafe/left | 鳳梨酥 | instance 1 | instance 1 | 100% → 100% | 0% → 0% | no → no | 0% | ok |
| pineapple-cake-on-cafe/down | 鳳梨酥 | instance 1 | instance 1 | 100% → 100% | 0% → 0% | no → no | 0% | ok |
| pineapple-cake-on-cafe/up | 鳳梨酥 | instance 1 | instance 1 | 100% → 100% | 0% → 0% | no → no | 0% | ok |
| pineapple-cake-on-cafe/point-off | 鳳梨酥 | instance 1 | instance 1 | 100% → 100% | 0% → 0% | no → no | 0% | ok |
| xiaolongbao-on-cafe/tight | 小籠包 | instance 1 | instance 1 | 100% → 100% | 0% → 0% | no → no | 0% | ok |
| xiaolongbao-on-cafe/loose | 小籠包 | instance 1 | instance 1 | 100% → 100% | 0% → 0% | no → no | 0% | ok |
| xiaolongbao-on-cafe/small | 小籠包 | instance 1 | instance 1 | 100% → 100% | 0% → 0% | no → no | 0% | ok |
| xiaolongbao-on-cafe/right | 小籠包 | instance 1 | instance 1 | 100% → 100% | 0% → 0% | no → no | 0% | ok |
| xiaolongbao-on-cafe/left | 小籠包 | instance 1 | instance 1 | 100% → 100% | 0% → 0% | no → no | 0% | ok |
| xiaolongbao-on-cafe/down | 小籠包 | instance 1 | instance 1 | 100% → 100% | 0% → 0% | no → no | 0% | ok |
| xiaolongbao-on-cafe/up | 小籠包 | instance 1 | instance 1 | 100% → 100% | 0% → 0% | no → no | 0% | ok |
| xiaolongbao-on-cafe/point-off | 小籠包 | instance 1 | instance 1 | 100% → 100% | 0% → 0% | no → no | 0% | ok |
| pomelo-on-cafe/tight | 柚子 | instance 1 | instance 1 | 100% → 100% | 0% → 0% | no → no | 0% | ok |
| pomelo-on-cafe/loose | 柚子 | instance 1 | instance 1 | 100% → 100% | 0% → 0% | no → no | 0% | ok |
| pomelo-on-cafe/small | 柚子 | instance 1 | instance 1 | 100% → 100% | 0% → 0% | no → no | 0% | ok |
| pomelo-on-cafe/right | 柚子 | instance 1 | instance 1 | 100% → 100% | 0% → 0% | no → no | 0% | ok |
| pomelo-on-cafe/left | 柚子 | instance 1 | instance 1 | 100% → 100% | 0% → 0% | no → no | 0% | ok |
| pomelo-on-cafe/down | 柚子 | instance 1 | instance 1 | 100% → 100% | 0% → 0% | no → no | 0% | ok |
| pomelo-on-cafe/up | 柚子 | instance 1 | instance 1 | 100% → 100% | 0% → 0% | no → no | 0% | ok |
| pomelo-on-cafe/point-off | 柚子 | instance 1 | instance 1 | 100% → 100% | 0% → 0% | no → no | 0% | ok |
| lint-roller-on-cafe/tight | 滾筒黏毛器 | CLIP [1] to box (0.23,0.39 0.37×0.45) | instance 1 + region | 100% → 100% | 0% → 0% | no → no | 0% | ok |
| lint-roller-on-cafe/loose | 滾筒黏毛器 | CLIP [1] to box (0.18,0.33 0.49×0.59) | instance 1 + region | 100% → 100% | 0% → 0% | no → no | 0% | ok |
| lint-roller-on-cafe/small | 滾筒黏毛器 | CLIP [1] to box (0.28,0.45 0.28×0.34) | instance 1 + region | 55% → 100% | 85% → 0% | no → no | 0% | ok |
| lint-roller-on-cafe/right | 滾筒黏毛器 | CLIP [1] to box (0.27,0.39 0.37×0.45) | instance 1 + region | 95% → 100% | 100% → 0% | no → no | 0% | ok |
| lint-roller-on-cafe/left | 滾筒黏毛器 | CLIP [1] to box (0.19,0.39 0.37×0.45) | instance 1 + region | 96% → 100% | 100% → 0% | no → no | 0% | ok |
| lint-roller-on-cafe/down | 滾筒黏毛器 | CLIP [1] to box (0.23,0.44 0.37×0.45) | instance 1 + region | 69% → 100% | 100% → 0% | no → no | 0% | ok |
| lint-roller-on-cafe/up | 滾筒黏毛器 | CLIP [1] to box (0.23,0.34 0.37×0.45) | instance 1 + region | 96% → 100% | 100% → 0% | no → no | 0% | ok |
| lint-roller-on-cafe/point-off | 滾筒黏毛器 | CLIP [1] to box (0.23,0.39 0.37×0.45) | instance 1 + region | 100% → 100% | 0% → 0% | no → no | 0% | ok |
| stool-on-street/tight | 塑膠椅 | instance 1 | instance 1 | 100% → 100% | 0% → 1% | no → no | 0% | ok |
| stool-on-street/loose | 塑膠椅 | instance 1 | instance 1 | 100% → 100% | 0% → 1% | no → no | 0% | ok |
| stool-on-street/small | 塑膠椅 | instance 1 | instance 1 + region | 100% → 100% | 0% → 2% | no → no | 0% | ok |
| stool-on-street/right | 塑膠椅 | CLIP [1] to box (0.41,0.39 0.44×0.41) | instance 1 + region | 97% → 100% | 100% → 1% | no → no | 0% | ok |
| stool-on-street/left | 塑膠椅 | instance 1 | instance 1 + region | 100% → 100% | 0% → 2% | no → no | 0% | ok |
| stool-on-street/down | 塑膠椅 | instance 1 | instance 1 | 100% → 100% | 0% → 1% | no → no | 0% | ok |
| stool-on-street/up | 塑膠椅 | CLIP [1] to box (0.36,0.35 0.44×0.41) | instance 1 + region | 98% → 100% | 100% → 2% | no → no | 0% | ok |
| stool-on-street/point-off | 塑膠椅 | instance 1 | instance 1 | 100% → 100% | 0% → 1% | no → no | 0% | ok |
| keys-on-street/tight | 鑰匙 | instance 1 | instance 1 | 100% → 100% | 0% → 0% | no → no | 0% | ok |
| keys-on-street/loose | 鑰匙 | instance 1 | instance 1 | 100% → 100% | 0% → 0% | no → no | 0% | ok |
| keys-on-street/small | 鑰匙 | instance 1 | instance 1 + region | 100% → 100% | 0% → 0% | no → no | 0% | ok |
| keys-on-street/right | 鑰匙 | CLIP [1] to box (0.34,0.39 0.62×0.41) | instance 1 + region | 98% → 100% | 100% → 0% | no → no | 0% | ok |
| keys-on-street/left | 鑰匙 | instance 1 | instance 1 | 100% → 100% | 0% → 0% | no → no | 0% | ok |
| keys-on-street/down | 鑰匙 | instance 1 | instance 1 | 100% → 100% | 0% → 0% | no → no | 0% | ok |
| keys-on-street/up | 鑰匙 | CLIP [1] to box (0.27,0.35 0.62×0.41) | instance 1 + region | 99% → 100% | 100% → 0% | no → no | 0% | ok |
| keys-on-street/point-off | 鑰匙 | instance 1 | instance 1 | 100% → 100% | 0% → 0% | no → no | 0% | ok |
| umbrella-on-street/tight | 雨傘 | CLIP [1] to box (0.46,0.39 0.24×0.41) | instance 1 + region | 100% → 100% | 0% → 6% | no → no | 0% | ok |
| umbrella-on-street/loose | 雨傘 | CLIP [1] to box (0.42,0.33 0.31×0.53) | instance 1 + region | 100% → 100% | 0% → 0% | no → no | 0% | ok |
| umbrella-on-street/small | 雨傘 | instance 1 | instance 1 + region | 100% → 100% | 0% → 6% | no → no | 0% | ok |
| umbrella-on-street/right | 雨傘 | CLIP [1] to box (0.49,0.39 0.24×0.41) | instance 1 + region | 98% → 100% | 100% → 6% | no → no | 0% | ok |
| umbrella-on-street/left | 雨傘 | CLIP [1] to box (0.43,0.39 0.24×0.41) | instance 1 + region | 99% → 100% | 100% → 6% | no → no | 0% | ok |
| umbrella-on-street/down | 雨傘 | instance 1 | instance 1 + region | 100% → 100% | 0% → 6% | no → no | 0% | ok |
| umbrella-on-street/up | 雨傘 | CLIP [1] to box (0.46,0.35 0.24×0.41) | instance 1 + region | 93% → 100% | 100% → 6% | no → no | 0% | ok |
| umbrella-on-street/point-off | 雨傘 | CLIP [1] to box (0.46,0.39 0.24×0.41) | instance 1 + region | 100% → 100% | 0% → 6% | no → no | 0% | ok |
| slippers-on-street/tight | 拖鞋 | instance 1 | instance 1 | 100% → 100% | 0% → 0% | no → no | 0% | ok |
| slippers-on-street/loose | 拖鞋 | instance 1 | instance 1 | 100% → 100% | 0% → 0% | no → no | 0% | ok |
| slippers-on-street/small | 拖鞋 | instance 1 | instance 1 + region | 100% → 50% | 0% → 0% | no → no | 0% | FAIL: covers 50% of the thing (< 85%) |
| slippers-on-street/right | 拖鞋 | instance 1 | instance 1 | 100% → 100% | 0% → 0% | no → no | 0% | ok |
| slippers-on-street/left | 拖鞋 | instance 1 | instance 1 | 100% → 100% | 0% → 0% | no → no | 0% | ok |
| slippers-on-street/down | 拖鞋 | instance 1 | instance 1 | 100% → 100% | 0% → 0% | no → no | 0% | ok |
| slippers-on-street/up | 拖鞋 | instance 1 | instance 1 | 100% → 100% | 0% → 0% | no → no | 0% | ok |
| slippers-on-street/point-off | 拖鞋 | instance 1 | instance 1 | 100% → 100% | 0% → 0% | no → no | 0% | ok |
| lantern-on-street/tight | 燈籠 | instance 1 | instance 1 | 100% → 100% | 0% → 0% | no → no | 0% | ok |
| lantern-on-street/loose | 燈籠 | instance 1 | instance 1 | 100% → 100% | 0% → 0% | no → no | 0% | ok |
| lantern-on-street/small | 燈籠 | instance 1 | instance 1 + region | 100% → 100% | 0% → 0% | no → no | 0% | ok |
| lantern-on-street/right | 燈籠 | instance 1 | instance 1 | 100% → 100% | 0% → 0% | no → no | 0% | ok |
| lantern-on-street/left | 燈籠 | instance 1 | instance 1 | 100% → 100% | 0% → 0% | no → no | 0% | ok |
| lantern-on-street/down | 燈籠 | instance 1 | instance 1 | 100% → 100% | 0% → 0% | no → no | 0% | ok |
| lantern-on-street/up | 燈籠 | instance 1 | instance 1 | 100% → 100% | 0% → 0% | no → no | 0% | ok |
| lantern-on-street/point-off | 燈籠 | instance 1 | instance 1 | 100% → 100% | 0% → 0% | no → no | 0% | ok |
| banana-on-street/tight | 香蕉 | instance 1 | instance 1 | 100% → 100% | 0% → 0% | no → no | 0% | ok |
| banana-on-street/loose | 香蕉 | instance 1 | instance 1 | 100% → 100% | 0% → 0% | no → no | 0% | ok |
| banana-on-street/small | 香蕉 | instance 1 | instance 1 + region | 100% → 100% | 0% → 0% | no → no | 0% | ok |
| banana-on-street/right | 香蕉 | instance 1 | instance 1 | 100% → 100% | 0% → 0% | no → no | 0% | ok |
| banana-on-street/left | 香蕉 | instance 1 | instance 1 | 100% → 100% | 0% → 0% | no → no | 0% | ok |
| banana-on-street/down | 香蕉 | instance 1 | instance 1 | 100% → 100% | 0% → 0% | no → no | 0% | ok |
| banana-on-street/up | 香蕉 | instance 1 | instance 1 | 100% → 100% | 0% → 0% | no → no | 0% | ok |
| banana-on-street/point-off | 香蕉 | instance 1 | instance 1 | 100% → 100% | 0% → 0% | no → no | 0% | ok |
| bubble-tea-cup-on-street/tight | 珍珠奶茶 | CLIP [1] to box (0.45,0.39 0.27×0.41) | instance 1 + region | 100% → 100% | 0% → 0% | no → no | 0% | ok |
| bubble-tea-cup-on-street/loose | 珍珠奶茶 | CLIP [1] to box (0.41,0.33 0.35×0.53) | instance 1 + region | 100% → 100% | 0% → 0% | no → no | 0% | ok |
| bubble-tea-cup-on-street/small | 珍珠奶茶 | instance 1 | instance 1 + region | 100% → 100% | 0% → 0% | no → no | 0% | ok |
| bubble-tea-cup-on-street/right | 珍珠奶茶 | CLIP [1] to box (0.48,0.39 0.27×0.41) | instance 1 + region | 100% → 100% | 100% → 0% | no → no | 0% | ok |
| bubble-tea-cup-on-street/left | 珍珠奶茶 | CLIP [1] to box (0.42,0.39 0.27×0.41) | instance 1 + region | 99% → 100% | 100% → 0% | no → no | 0% | ok |
| bubble-tea-cup-on-street/down | 珍珠奶茶 | instance 1 | instance 1 + region | 100% → 100% | 0% → 0% | no → no | 0% | ok |
| bubble-tea-cup-on-street/up | 珍珠奶茶 | CLIP [1] to box (0.45,0.35 0.27×0.41) | instance 1 + region | 93% → 100% | 100% → 0% | no → no | 0% | ok |
| bubble-tea-cup-on-street/point-off | 珍珠奶茶 | CLIP [1] to box (0.45,0.39 0.27×0.41) | instance 1 + region | 100% → 100% | 0% → 0% | no → no | 0% | ok |
| succulent-on-street/tight | 多肉植物 | instance 1 | instance 1 | 100% → 100% | 0% → 0% | no → no | 0% | ok |
| succulent-on-street/loose | 多肉植物 | instance 1 | instance 1 | 100% → 100% | 0% → 0% | no → no | 0% | ok |
| succulent-on-street/small | 多肉植物 | instance 1 | instance 1 + region | 100% → 100% | 0% → 0% | no → no | 0% | ok |
| succulent-on-street/right | 多肉植物 | instance 1 | instance 1 | 100% → 100% | 0% → 0% | no → no | 0% | ok |
| succulent-on-street/left | 多肉植物 | instance 1 | instance 1 | 100% → 100% | 0% → 0% | no → no | 0% | ok |
| succulent-on-street/down | 多肉植物 | instance 1 | instance 1 | 100% → 100% | 0% → 0% | no → no | 0% | ok |
| succulent-on-street/up | 多肉植物 | instance 1 | instance 1 + region | 100% → 100% | 0% → 0% | no → no | 0% | ok |
| succulent-on-street/point-off | 多肉植物 | instance 1 | instance 1 | 100% → 100% | 0% → 0% | no → no | 0% | ok |
| cola-on-street/tight | 可樂 | instance 1 | instance 1 + region | 100% → 100% | 0% → 0% | no → no | 0% | ok |
| cola-on-street/loose | 可樂 | instance 1 | instance 1 | 100% → 100% | 0% → 0% | no → no | 0% | ok |
| cola-on-street/small | 可樂 | instance 1 | instance 1 + region | 100% → 100% | 0% → 0% | no → no | 0% | ok |
| cola-on-street/right | 可樂 | instance 1 | instance 1 + region | 100% → 100% | 0% → 0% | no → no | 0% | ok |
| cola-on-street/left | 可樂 | instance 1 | instance 1 + region | 100% → 100% | 0% → 0% | no → no | 0% | ok |
| cola-on-street/down | 可樂 | instance 1 | instance 1 | 100% → 100% | 0% → 0% | no → no | 0% | ok |
| cola-on-street/up | 可樂 | instance 1 | instance 1 + region | 100% → 100% | 0% → 0% | no → no | 0% | ok |
| cola-on-street/point-off | 可樂 | instance 1 | instance 1 + region | 100% → 100% | 0% → 0% | no → no | 0% | ok |
| juice-on-street/tight | 果汁 | instance 1 | instance 1 | 100% → 100% | 0% → 0% | no → no | 0% | ok |
| juice-on-street/loose | 果汁 | instance 1 | instance 1 | 100% → 100% | 0% → 0% | no → no | 0% | ok |
| juice-on-street/small | 果汁 | instance 1 | instance 1 + region | 100% → 100% | 0% → 0% | no → no | 0% | ok |
| juice-on-street/right | 果汁 | instance 1 | instance 1 + region | 100% → 100% | 0% → 0% | no → no | 0% | ok |
| juice-on-street/left | 果汁 | instance 1 | instance 1 + region | 100% → 100% | 0% → 0% | no → no | 0% | ok |
| juice-on-street/down | 果汁 | instance 1 | instance 1 | 100% → 100% | 0% → 0% | no → no | 0% | ok |
| juice-on-street/up | 果汁 | instance 1 | instance 1 + region | 100% → 100% | 0% → 0% | no → no | 0% | ok |
| juice-on-street/point-off | 果汁 | instance 1 | instance 1 | 100% → 100% | 0% → 0% | no → no | 0% | ok |
| oolong-on-street/tight | 烏龍茶 | instance 1 | instance 1 + region | 100% → 100% | 0% → 0% | no → no | 0% | ok |
| oolong-on-street/loose | 烏龍茶 | instance 1 | instance 1 + region | 100% → 100% | 0% → 0% | no → no | 0% | ok |
| oolong-on-street/small | 烏龍茶 | instance 1 | instance 1 + region | 100% → 100% | 0% → 0% | no → no | 0% | ok |
| oolong-on-street/right | 烏龍茶 | instance 1 | instance 1 + region | 100% → 100% | 0% → 0% | no → no | 0% | ok |
| oolong-on-street/left | 烏龍茶 | instance 1 | instance 1 + region | 100% → 100% | 0% → 0% | no → no | 0% | ok |
| oolong-on-street/down | 烏龍茶 | instance 1 | instance 1 + region | 100% → 100% | 0% → 0% | no → no | 0% | ok |
| oolong-on-street/up | 烏龍茶 | instance 1 | instance 1 + region | 100% → 100% | 0% → 0% | no → no | 0% | ok |
| oolong-on-street/point-off | 烏龍茶 | instance 1 | instance 1 + region | 100% → 100% | 0% → 0% | no → no | 0% | ok |
| mango-on-street/tight | 芒果 | instance 1 | instance 1 | 100% → 100% | 0% → 0% | no → no | 0% | ok |
| mango-on-street/loose | 芒果 | instance 1 | instance 1 | 100% → 100% | 0% → 0% | no → no | 0% | ok |
| mango-on-street/small | 芒果 | instance 1 | instance 1 + region | 100% → 100% | 0% → 0% | no → no | 0% | ok |
| mango-on-street/right | 芒果 | instance 1 | instance 1 + region | 100% → 100% | 0% → 0% | no → no | 0% | ok |
| mango-on-street/left | 芒果 | instance 1 | instance 1 + region | 100% → 100% | 0% → 0% | no → no | 0% | ok |
| mango-on-street/down | 芒果 | instance 1 | instance 1 | 100% → 100% | 0% → 0% | no → no | 0% | ok |
| mango-on-street/up | 芒果 | instance 1 | instance 1 + region | 100% → 100% | 0% → 0% | no → no | 0% | ok |
| mango-on-street/point-off | 芒果 | instance 1 | instance 1 | 100% → 100% | 0% → 0% | no → no | 0% | ok |
| pineapple-cake-on-street/tight | 鳳梨酥 | instance 1 | instance 1 | 100% → 100% | 0% → 0% | no → no | 0% | ok |
| pineapple-cake-on-street/loose | 鳳梨酥 | instance 1 | instance 1 | 100% → 100% | 0% → 0% | no → no | 0% | ok |
| pineapple-cake-on-street/small | 鳳梨酥 | instance 1 | instance 1 + region | 100% → 100% | 0% → 0% | no → no | 0% | ok |
| pineapple-cake-on-street/right | 鳳梨酥 | instance 1 | instance 1 | 100% → 100% | 0% → 0% | no → no | 0% | ok |
| pineapple-cake-on-street/left | 鳳梨酥 | instance 1 | instance 1 | 100% → 100% | 0% → 0% | no → no | 0% | ok |
| pineapple-cake-on-street/down | 鳳梨酥 | instance 1 | instance 1 | 100% → 100% | 0% → 0% | no → no | 0% | ok |
| pineapple-cake-on-street/up | 鳳梨酥 | instance 1 | instance 1 | 100% → 100% | 0% → 0% | no → no | 0% | ok |
| pineapple-cake-on-street/point-off | 鳳梨酥 | instance 1 | instance 1 | 100% → 100% | 0% → 0% | no → no | 0% | ok |
| xiaolongbao-on-street/tight | 小籠包 | instance 1 | instance 1 | 100% → 100% | 0% → 0% | no → no | 0% | ok |
| xiaolongbao-on-street/loose | 小籠包 | instance 1 | instance 1 | 100% → 100% | 0% → 0% | no → no | 0% | ok |
| xiaolongbao-on-street/small | 小籠包 | instance 1 | instance 1 + region | 100% → 100% | 0% → 0% | no → no | 0% | ok |
| xiaolongbao-on-street/right | 小籠包 | instance 1 | instance 1 | 100% → 100% | 0% → 0% | no → no | 0% | ok |
| xiaolongbao-on-street/left | 小籠包 | instance 1 | instance 1 | 100% → 100% | 0% → 0% | no → no | 0% | ok |
| xiaolongbao-on-street/down | 小籠包 | instance 1 | instance 1 | 100% → 100% | 0% → 0% | no → no | 0% | ok |
| xiaolongbao-on-street/up | 小籠包 | instance 1 | instance 1 | 100% → 100% | 0% → 0% | no → no | 0% | ok |
| xiaolongbao-on-street/point-off | 小籠包 | instance 1 | instance 1 | 100% → 100% | 0% → 0% | no → no | 0% | ok |
| pomelo-on-street/tight | 柚子 | instance 1 | instance 1 | 100% → 100% | 0% → 0% | no → no | 0% | ok |
| pomelo-on-street/loose | 柚子 | instance 1 | instance 1 | 100% → 100% | 0% → 0% | no → no | 0% | ok |
| pomelo-on-street/small | 柚子 | instance 1 | instance 1 + region | 100% → 100% | 0% → 0% | no → no | 0% | ok |
| pomelo-on-street/right | 柚子 | instance 1 | instance 1 | 100% → 100% | 0% → 0% | no → no | 0% | ok |
| pomelo-on-street/left | 柚子 | instance 1 | instance 1 | 100% → 100% | 0% → 0% | no → no | 0% | ok |
| pomelo-on-street/down | 柚子 | instance 1 | instance 1 | 100% → 100% | 0% → 0% | no → no | 0% | ok |
| pomelo-on-street/up | 柚子 | instance 1 | instance 1 | 100% → 100% | 0% → 0% | no → no | 0% | ok |
| pomelo-on-street/point-off | 柚子 | instance 1 | instance 1 | 100% → 100% | 0% → 0% | no → no | 0% | ok |
| lint-roller-on-street/tight | 滾筒黏毛器 | CLIP [1] to box (0.41,0.39 0.34×0.41) | instance 1 + region | 100% → 100% | 0% → 0% | no → no | 0% | ok |
| lint-roller-on-street/loose | 滾筒黏毛器 | instance 1 | instance 1 | 100% → 100% | 0% → 0% | no → no | 0% | ok |
| lint-roller-on-street/small | 滾筒黏毛器 | CLIP [1] to box (0.45,0.44 0.26×0.31) | instance 1 + region | 56% → 100% | 86% → 0% | no → no | 0% | ok |
| lint-roller-on-street/right | 滾筒黏毛器 | CLIP [1] to box (0.45,0.39 0.34×0.41) | instance 1 + region | 96% → 100% | 100% → 0% | no → no | 0% | ok |
| lint-roller-on-street/left | 滾筒黏毛器 | CLIP [1] to box (0.37,0.39 0.34×0.41) | instance 1 + region | 96% → 100% | 100% → 0% | no → no | 0% | ok |
| lint-roller-on-street/down | 滾筒黏毛器 | CLIP [1] to box (0.41,0.44 0.34×0.41) | instance 1 + region | 69% → 100% | 100% → 0% | no → no | 0% | ok |
| lint-roller-on-street/up | 滾筒黏毛器 | CLIP [1] to box (0.41,0.35 0.34×0.41) | instance 1 + region | 96% → 100% | 100% → 0% | no → no | 0% | ok |
| lint-roller-on-street/point-off | 滾筒黏毛器 | CLIP [1] to box (0.41,0.39 0.34×0.41) | instance 1 + region | 100% → 100% | 0% → 0% | no → no | 0% | ok |
| cola+pineapple-cake-on-floor/tight | 可樂 | CLIP [1] to box (0.16,0.32 0.33×0.45) | part of [1] (19292 px) | 100% → 100% | 2% → 2% | no → no | 0% | ok |
| cola+pineapple-cake-on-floor/tight | 鳳梨酥 | CLIP [1] to box (0.28,0.41 0.63×0.39) | part of [1] (37510 px) | 100% → 100% | 0% → 0% | no → no | 0% | ok |
| cola+pineapple-cake-on-floor/loose | 可樂 | CLIP [1] to box (0.12,0.26 0.43×0.59) | no mask, no cut-out | 100% → 0% | 2% → 0% | no → no | 0% | ok |
| cola+pineapple-cake-on-floor/loose | 鳳梨酥 | instance 1 | part of [1] (56610 px) | 100% → 100% | 0% → 0% | no → no | 27% | FAIL: 27% of it is another named thing |
| cola+pineapple-cake-on-floor/small | 可樂 | CLIP [1] to box (0.20,0.38 0.25×0.34) | part of [1] (56533 px), no cut-out | 76% → 0% | 100% → 0% | no → no | 0% | ok |
| cola+pineapple-cake-on-floor/small | 鳳梨酥 | CLIP [1] to box (0.35,0.45 0.48×0.30) | part of [1] (52654 px), no cut-out | 87% → 0% | 100% → 0% | no → no | 0% | ok |
| cola+pineapple-cake-on-floor/right | 可樂 | CLIP [1] to box (0.20,0.32 0.33×0.45) | part of [1] (56083 px), no cut-out | 92% → 0% | 100% → 0% | no → no | 0% | ok |
| cola+pineapple-cake-on-floor/right | 鳳梨酥 | CLIP [1] to box (0.35,0.41 0.63×0.39) | part of [1] (37287 px) | 96% → 100% | 100% → 59% | no → no | 0% | FAIL: a straight cut through the thing along 59% of a line (column 281 of 900) |
| cola+pineapple-cake-on-floor/left | 可樂 | CLIP [1] to box (0.13,0.32 0.33×0.45) | part of [1] (19269 px) | 99% → 100% | 100% → 2% | no → no | 0% | ok |
| cola+pineapple-cake-on-floor/left | 鳳梨酥 | CLIP [1] to box (0.21,0.41 0.63×0.39) | part of [1] (52992 px), no cut-out | 96% → 0% | 100% → 0% | no → no | 0% | ok |
| cola+pineapple-cake-on-floor/down | 可樂 | CLIP [1] to box (0.16,0.37 0.33×0.45) | part of [1] (19292 px) | 97% → 100% | 2% → 2% | no → no | 0% | ok |
| cola+pineapple-cake-on-floor/down | 鳳梨酥 | CLIP [1] to box (0.28,0.45 0.63×0.39) | part of [1] (37502 px) | 98% → 100% | 100% → 0% | no → no | 0% | ok |
| cola+pineapple-cake-on-floor/up | 可樂 | CLIP [1] to box (0.16,0.27 0.33×0.45) | part of [1] (19284 px) | 92% → 100% | 100% → 2% | no → no | 0% | ok |
| cola+pineapple-cake-on-floor/up | 鳳梨酥 | CLIP [1] to box (0.28,0.36 0.63×0.39) | part of [1] (52887 px), no cut-out | 98% → 0% | 100% → 0% | no → no | 0% | ok |
| cola+pineapple-cake-on-floor/point-off | 可樂 | CLIP [1] to box (0.16,0.32 0.33×0.45) | part of [1] (19292 px) | 100% → 100% | 2% → 2% | no → no | 0% | ok |
| cola+pineapple-cake-on-floor/point-off | 鳳梨酥 | CLIP [1] to box (0.28,0.41 0.63×0.39) | part of [1] (37510 px) | 100% → 100% | 0% → 0% | no → no | 0% | ok |
| cola+pineapple-cake-on-cafe/tight | 可樂 | CLIP [1] to box (0.16,0.32 0.33×0.45) | part of [1] (21860 px) | 100% → 100% | 5% → 5% | no → no | 1% | ok |
| cola+pineapple-cake-on-cafe/tight | 鳳梨酥 | CLIP [1] to box (0.28,0.41 0.63×0.39) | part of [1] (47042 px) | 100% → 100% | 0% → 0% | no → no | 0% | ok |
| cola+pineapple-cake-on-cafe/loose | 可樂 | CLIP [1] to box (0.12,0.26 0.43×0.59) | no mask, no cut-out | 100% → 0% | 5% → 0% | no → no | 0% | ok |
| cola+pineapple-cake-on-cafe/loose | 鳳梨酥 | instance 1 | part of [1] (67327 px) | 100% → 100% | 0% → 0% | no → no | 23% | FAIL: 23% of it is another named thing |
| cola+pineapple-cake-on-cafe/small | 可樂 | CLIP [1] to box (0.20,0.38 0.25×0.34) | part of [1] (58219 px), no cut-out | 76% → 0% | 100% → 0% | no → no | 0% | ok |
| cola+pineapple-cake-on-cafe/small | 鳳梨酥 | CLIP [1] to box (0.35,0.45 0.48×0.30) | part of [1] (61674 px), no cut-out | 87% → 0% | 100% → 0% | no → no | 0% | ok |
| cola+pineapple-cake-on-cafe/right | 可樂 | CLIP [1] to box (0.20,0.32 0.33×0.45) | part of [1] (58099 px), no cut-out | 92% → 0% | 100% → 0% | no → no | 0% | ok |
| cola+pineapple-cake-on-cafe/right | 鳳梨酥 | CLIP [1] to box (0.35,0.41 0.63×0.39) | part of [1] (46619 px) | 96% → 100% | 100% → 59% | no → no | 0% | FAIL: a straight cut through the thing along 59% of a line (column 281 of 900) |
| cola+pineapple-cake-on-cafe/left | 可樂 | CLIP [1] to box (0.13,0.32 0.33×0.45) | part of [1] (21659 px) | 99% → 100% | 100% → 5% | no → no | 1% | ok |
| cola+pineapple-cake-on-cafe/left | 鳳梨酥 | CLIP [1] to box (0.21,0.41 0.63×0.39) | part of [1] (62139 px), no cut-out | 96% → 0% | 100% → 0% | no → no | 0% | ok |
| cola+pineapple-cake-on-cafe/down | 可樂 | CLIP [1] to box (0.16,0.37 0.33×0.45) | part of [1] (21819 px) | 97% → 100% | 5% → 5% | no → no | 1% | ok |
| cola+pineapple-cake-on-cafe/down | 鳳梨酥 | CLIP [1] to box (0.28,0.45 0.63×0.39) | part of [1] (46837 px) | 98% → 100% | 100% → 0% | no → no | 0% | ok |
| cola+pineapple-cake-on-cafe/up | 可樂 | CLIP [1] to box (0.16,0.27 0.33×0.45) | part of [1] (21748 px) | 92% → 100% | 100% → 5% | no → no | 1% | ok |
| cola+pineapple-cake-on-cafe/up | 鳳梨酥 | CLIP [1] to box (0.28,0.36 0.63×0.39) | part of [1] (62006 px), no cut-out | 98% → 0% | 100% → 0% | no → no | 0% | ok |
| cola+pineapple-cake-on-cafe/point-off | 可樂 | CLIP [1] to box (0.16,0.32 0.33×0.45) | part of [1] (21860 px) | 100% → 100% | 5% → 5% | no → no | 1% | ok |
| cola+pineapple-cake-on-cafe/point-off | 鳳梨酥 | CLIP [1] to box (0.28,0.41 0.63×0.39) | part of [1] (47042 px) | 100% → 100% | 0% → 0% | no → no | 0% | ok |
| banana+mango-on-floor/tight | 香蕉 | CLIP [1] to box (0.00,0.32 0.73×0.45) | part of [1] (46082 px) | 100% → 100% | 0% → 0% | no → no | 0% | ok |
| banana+mango-on-floor/tight | 芒果 | CLIP [1] to box (0.68,0.41 0.32×0.39) | part of [1] (22125 px) | 100% → 100% | 0% → 0% | no → no | 0% | ok |
| banana+mango-on-floor/loose | 香蕉 | CLIP [1] to box (0.00,0.26 0.84×0.59) | part of [1] (46174 px) | 100% → 100% | 0% → 0% | no → no | 0% | ok |
| banana+mango-on-floor/loose | 芒果 | CLIP [1] to box (0.63,0.35 0.37×0.51) | part of [1] (22541 px) | 100% → 100% | 0% → 0% | no → no | 2% | ok |
| banana+mango-on-floor/small | 香蕉 | CLIP [1] to box (0.06,0.38 0.58×0.34) | part of [1] (46012 px) | 87% → 100% | 100% → 0% | no → no | 0% | ok |
| banana+mango-on-floor/small | 芒果 | CLIP [1] to box (0.72,0.45 0.26×0.30) | part of [1] (22237 px) | 87% → 100% | 100% → 0% | no → no | 0% | ok |
| banana+mango-on-floor/right | 香蕉 | CLIP [1] to box (0.06,0.32 0.76×0.45) | part of [1] (67312 px), no cut-out | 95% → 0% | 100% → 0% | no → no | 0% | ok |
| banana+mango-on-floor/right | 芒果 | CLIP [1] to box (0.72,0.41 0.28×0.39) | part of [1] (21883 px) | 97% → 100% | 100% → 5% | no → no | 0% | ok |
| banana+mango-on-floor/left | 香蕉 | CLIP [1] to box (0.00,0.32 0.64×0.45) | part of [1] (45665 px) | 98% → 100% | 100% → 12% | no → no | 0% | ok |
| banana+mango-on-floor/left | 芒果 | CLIP [1] to box (0.64,0.41 0.34×0.39) | part of [1] (65997 px), no cut-out | 97% → 0% | 100% → 0% | no → no | 0% | ok |
| banana+mango-on-floor/down | 香蕉 | CLIP [1] to box (0.00,0.37 0.73×0.45) | part of [1] (46097 px) | 99% → 100% | 100% → 0% | no → no | 0% | ok |
| banana+mango-on-floor/down | 芒果 | CLIP [1] to box (0.68,0.45 0.32×0.39) | part of [1] (22125 px) | 98% → 100% | 100% → 0% | no → no | 0% | ok |
| banana+mango-on-floor/up | 香蕉 | CLIP [1] to box (0.00,0.27 0.73×0.45) | part of [1] (46134 px) | 97% → 100% | 100% → 0% | no → no | 0% | ok |
| banana+mango-on-floor/up | 芒果 | CLIP [1] to box (0.68,0.36 0.32×0.39) | part of [1] (22125 px) | 97% → 100% | 100% → 0% | no → no | 0% | ok |
| banana+mango-on-floor/point-off | 香蕉 | CLIP [1] to box (0.00,0.32 0.73×0.45) | part of [1] (46082 px) | 100% → 100% | 0% → 0% | no → no | 0% | ok |
| banana+mango-on-floor/point-off | 芒果 | CLIP [1] to box (0.68,0.41 0.32×0.39) | part of [1] (22125 px) | 100% → 100% | 0% → 0% | no → no | 0% | ok |
| banana+mango-on-cafe/tight | 香蕉 | CLIP [1] to box (0.00,0.32 0.73×0.45) | part of [1] (60116 px) | 100% → 100% | 0% → 0% | no → no | 0% | ok |
| banana+mango-on-cafe/tight | 芒果 | CLIP [1] to box (0.68,0.41 0.32×0.39) | part of [1] (36740 px), no cut-out | 100% → 0% | 0% → 0% | no → no | 0% | ok |
| banana+mango-on-cafe/loose | 香蕉 | CLIP [1] to box (0.00,0.26 0.84×0.59) | part of [1] (60730 px) | 100% → 100% | 0% → 0% | no → no | 0% | ok |
| banana+mango-on-cafe/loose | 芒果 | CLIP [1] to box (0.63,0.35 0.37×0.51) | part of [1] (23448 px) | 100% → 100% | 0% → 0% | no → no | 2% | ok |
| banana+mango-on-cafe/small | 香蕉 | CLIP [1] to box (0.06,0.38 0.58×0.34) | part of [1] (60412 px) | 87% → 100% | 100% → 0% | no → no | 0% | ok |
| banana+mango-on-cafe/small | 芒果 | CLIP [1] to box (0.72,0.45 0.26×0.30) | part of [1] (37234 px) | 87% → 100% | 100% → 0% | no → no | 0% | ok |
| banana+mango-on-cafe/right | 香蕉 | CLIP [1] to box (0.06,0.32 0.76×0.45) | part of [1] (81874 px) | 95% → 100% | 100% → 0% | no → no | 0% | ok |
| banana+mango-on-cafe/right | 芒果 | CLIP [1] to box (0.72,0.41 0.28×0.39) | part of [1] (22130 px) | 97% → 100% | 100% → 0% | no → no | 0% | ok |
| banana+mango-on-cafe/left | 香蕉 | CLIP [1] to box (0.00,0.32 0.64×0.45) | part of [1] (59590 px) | 98% → 100% | 100% → 7% | no → no | 0% | ok |
| banana+mango-on-cafe/left | 芒果 | CLIP [1] to box (0.64,0.41 0.34×0.39) | part of [1] (81524 px), no cut-out | 97% → 0% | 100% → 0% | no → no | 0% | ok |
| banana+mango-on-cafe/down | 香蕉 | CLIP [1] to box (0.00,0.37 0.73×0.45) | part of [1] (60125 px) | 99% → 100% | 100% → 0% | no → no | 0% | ok |
| banana+mango-on-cafe/down | 芒果 | CLIP [1] to box (0.68,0.45 0.32×0.39) | part of [1] (36710 px), no cut-out | 98% → 0% | 100% → 0% | no → no | 0% | ok |
| banana+mango-on-cafe/up | 香蕉 | CLIP [1] to box (0.00,0.27 0.73×0.45) | part of [1] (60275 px) | 97% → 100% | 100% → 0% | no → no | 0% | ok |
| banana+mango-on-cafe/up | 芒果 | CLIP [1] to box (0.68,0.36 0.32×0.39) | part of [1] (22867 px) | 97% → 100% | 100% → 0% | no → no | 0% | ok |
| banana+mango-on-cafe/point-off | 香蕉 | CLIP [1] to box (0.00,0.32 0.73×0.45) | part of [1] (60116 px) | 100% → 100% | 0% → 0% | no → no | 0% | ok |
| banana+mango-on-cafe/point-off | 芒果 | CLIP [1] to box (0.68,0.41 0.32×0.39) | part of [1] (36740 px), no cut-out | 100% → 0% | 0% → 0% | no → no | 0% | ok |
| keys+slippers-on-floor/tight | 鑰匙 | CLIP [1] to box (0.00,0.32 0.67×0.45) | part of [1] (25064 px), no cut-out | 100% → 0% | 2% → 0% | no → no | 0% | ok |
| keys+slippers-on-floor/tight | 拖鞋 | instance 2 | part of [1, 2] (28589 px), no cut-out | 50% → 0% | 0% → 0% | no → no | 0% | ok |
| keys+slippers-on-floor/loose | 鑰匙 | instance 1 | instance 1 | 100% → 100% | 2% → 2% | no → no | 34% | FAIL: 34% of it is another named thing |
| keys+slippers-on-floor/loose | 拖鞋 | instance 2 | instance 2 | 50% → 50% | 0% → 0% | no → no | 0% | FAIL: covers 50% of the thing (< 85%) |
| keys+slippers-on-floor/small | 鑰匙 | CLIP [1] to box (0.07,0.38 0.52×0.34) | part of [1] (24994 px) | 96% → 100% | 100% → 2% | no → no | 0% | ok |
| keys+slippers-on-floor/small | 拖鞋 | instance 2 | part of [1, 2] (28589 px), no cut-out | 50% → 0% | 0% → 0% | no → no | 0% | ok |
| keys+slippers-on-floor/right | 鑰匙 | CLIP [1] to box (0.06,0.32 0.69×0.45) | instance 1 | 98% → 100% | 100% → 2% | no → no | 34% | FAIL: 34% of it is another named thing |
| keys+slippers-on-floor/right | 拖鞋 | instance 2 | instance 2 | 50% → 50% | 0% → 0% | no → no | 0% | FAIL: covers 50% of the thing (< 85%) |
| keys+slippers-on-floor/left | 鑰匙 | CLIP [1] to box (0.00,0.32 0.59×0.45) | part of [1] (24994 px) | 100% → 100% | 100% → 2% | no → no | 0% | ok |
| keys+slippers-on-floor/left | 拖鞋 | instance 2 | part of [1, 2] (28589 px) | 50% → 100% | 0% → 0% | no → no | 0% | ok |
| keys+slippers-on-floor/down | 鑰匙 | CLIP [1] to box (0.00,0.37 0.67×0.45) | part of [1] (25066 px), no cut-out | 100% → 0% | 2% → 0% | no → no | 0% | ok |
| keys+slippers-on-floor/down | 拖鞋 | instance 2 | part of [1, 2] (28589 px), no cut-out | 50% → 0% | 0% → 0% | no → no | 0% | ok |
| keys+slippers-on-floor/up | 鑰匙 | CLIP [1] to box (0.00,0.27 0.67×0.45) | part of [1] (25049 px), no cut-out | 99% → 0% | 100% → 0% | no → no | 0% | ok |
| keys+slippers-on-floor/up | 拖鞋 | instance 2 | part of [1, 2] (28589 px), no cut-out | 50% → 0% | 0% → 0% | no → no | 0% | ok |
| keys+slippers-on-floor/point-off | 鑰匙 | CLIP [1] to box (0.00,0.32 0.67×0.45) | part of [1] (25064 px) | 100% → 100% | 2% → 2% | no → no | 0% | ok |
| keys+slippers-on-floor/point-off | 拖鞋 | CLIP [1] to box (0.58,0.41 0.42×0.39) | part of [1, 2] (28589 px) | 50% → 100% | 0% → 0% | no → no | 0% | ok |
| keys+slippers-on-cafe/tight | 鑰匙 | CLIP [1] to box (0.00,0.32 0.67×0.45) | part of [1] (36377 px), no cut-out | 100% → 0% | 5% → 0% | no → no | 0% | ok |
| keys+slippers-on-cafe/tight | 拖鞋 | CLIP [1] to box (0.58,0.41 0.42×0.39) | part of [1] (14600 px), no cut-out | 50% → 0% | 0% → 0% | no → no | 0% | ok |
| keys+slippers-on-cafe/loose | 鑰匙 | instance 1 | part of [1] (50265 px) | 100% → 100% | 5% → 0% | no → no | 26% | FAIL: 26% of it is another named thing |
| keys+slippers-on-cafe/loose | 拖鞋 | CLIP [1] to box (0.52,0.35 0.48×0.51) | no mask, no cut-out | 50% → 0% | 0% → 0% | no → no | 0% | ok |
| keys+slippers-on-cafe/small | 鑰匙 | CLIP [1] to box (0.07,0.38 0.52×0.34) | part of [1] (36182 px), no cut-out | 96% → 0% | 100% → 0% | no → no | 0% | ok |
| keys+slippers-on-cafe/small | 拖鞋 | CLIP [1] to box (0.63,0.45 0.33×0.30) | part of [1] (14596 px), no cut-out | 40% → 0% | 100% → 0% | no → no | 0% | ok |
| keys+slippers-on-cafe/right | 鑰匙 | instance 1 | part of [1] (50104 px) | 100% → 100% | 5% → 5% | no → no | 27% | FAIL: 27% of it is another named thing |
| keys+slippers-on-cafe/right | 拖鞋 | CLIP [1] to box (0.63,0.41 0.37×0.39) | part of [1] (40927 px), no cut-out | 46% → 0% | 100% → 0% | no → no | 0% | ok |
| keys+slippers-on-cafe/left | 鑰匙 | CLIP [1] to box (0.00,0.32 0.59×0.45) | part of [1] (35511 px) | 100% → 100% | 100% → 5% | no → no | 0% | ok |
| keys+slippers-on-cafe/left | 拖鞋 | CLIP [1] to box (0.53,0.41 0.44×0.39) | part of [1] (41925 px), no cut-out | 50% → 0% | 0% → 0% | no → no | 0% | ok |
| keys+slippers-on-cafe/down | 鑰匙 | CLIP [1] to box (0.00,0.37 0.67×0.45) | part of [1] (36361 px) | 100% → 100% | 5% → 5% | no → no | 0% | ok |
| keys+slippers-on-cafe/down | 拖鞋 | CLIP [1] to box (0.58,0.45 0.42×0.39) | part of [1] (41297 px), no cut-out | 48% → 0% | 50% → 0% | no → no | 0% | ok |
| keys+slippers-on-cafe/up | 鑰匙 | CLIP [1] to box (0.00,0.27 0.67×0.45) | part of [1] (36455 px), no cut-out | 99% → 0% | 100% → 0% | no → no | 0% | ok |
| keys+slippers-on-cafe/up | 拖鞋 | CLIP [1] to box (0.58,0.36 0.42×0.39) | part of [1] (14600 px), no cut-out | 48% → 0% | 50% → 0% | no → no | 0% | ok |
| keys+slippers-on-cafe/point-off | 鑰匙 | CLIP [1] to box (0.00,0.32 0.67×0.45) | part of [1] (36377 px) | 100% → 100% | 5% → 5% | no → no | 0% | ok |
| keys+slippers-on-cafe/point-off | 拖鞋 | CLIP [1] to box (0.58,0.41 0.42×0.39) | part of [1] (14600 px), no cut-out | 50% → 0% | 0% → 0% | no → no | 0% | ok |
| bubble-tea-cup+xiaolongbao-on-floor/tight | 珍珠奶茶 | CLIP [1] to box (0.18,0.32 0.30×0.45) | part of [1] (6066 px) | 100% → 100% | 0% → 0% | no → no | 8% | ok |
| bubble-tea-cup+xiaolongbao-on-floor/tight | 小籠包 | instance 1 | part of [1] (46524 px) | 100% → 100% | 0% → 3% | no → no | 1% | ok |
| bubble-tea-cup+xiaolongbao-on-floor/loose | 珍珠奶茶 | CLIP [1] to box (0.14,0.26 0.38×0.59) | part of [1] (50881 px), no cut-out | 100% → 0% | 0% → 0% | no → no | 0% | ok |
| bubble-tea-cup+xiaolongbao-on-floor/loose | 小籠包 | instance 1 | part of [1] (46170 px) | 100% → 100% | 0% → 14% | no → no | 1% | ok |
| bubble-tea-cup+xiaolongbao-on-floor/small | 珍珠奶茶 | CLIP [1] to box (0.22,0.38 0.22×0.34) | part of [1] (51153 px), no cut-out | 81% → 0% | 100% → 0% | no → no | 0% | ok |
| bubble-tea-cup+xiaolongbao-on-floor/small | 小籠包 | CLIP [1] to box (0.32,0.45 0.48×0.30) | part of [1] (45804 px) | 82% → 100% | 100% → 14% | no → no | 0% | ok |
| bubble-tea-cup+xiaolongbao-on-floor/right | 珍珠奶茶 | CLIP [1] to box (0.21,0.32 0.30×0.45) | part of [1] (50873 px), no cut-out | 99% → 0% | 100% → 0% | no → no | 0% | ok |
| bubble-tea-cup+xiaolongbao-on-floor/right | 小籠包 | CLIP [1] to box (0.32,0.41 0.63×0.39) | part of [1] (45840 px) | 96% → 100% | 100% → 14% | no → no | 0% | ok |
| bubble-tea-cup+xiaolongbao-on-floor/left | 珍珠奶茶 | CLIP [1] to box (0.15,0.32 0.30×0.45) | part of [1] (5934 px) | 100% → 100% | 0% → 0% | no → no | 6% | ok |
| bubble-tea-cup+xiaolongbao-on-floor/left | 小籠包 | instance 1 | part of [1] (50428 px) | 100% → 100% | 0% → 3% | no → no | 7% | ok |
| bubble-tea-cup+xiaolongbao-on-floor/down | 珍珠奶茶 | CLIP [1] to box (0.18,0.37 0.30×0.45) | part of [1] (6070 px) | 99% → 100% | 0% → 0% | no → no | 8% | ok |
| bubble-tea-cup+xiaolongbao-on-floor/down | 小籠包 | instance 1 | part of [1] (46503 px) | 100% → 100% | 0% → 3% | no → no | 1% | ok |
| bubble-tea-cup+xiaolongbao-on-floor/up | 珍珠奶茶 | CLIP [1] to box (0.18,0.27 0.30×0.45) | part of [1] (6008 px) | 85% → 100% | 100% → 0% | no → no | 8% | ok |
| bubble-tea-cup+xiaolongbao-on-floor/up | 小籠包 | instance 1 | part of [1] (51078 px) | 100% → 100% | 0% → 0% | no → no | 8% | ok |
| bubble-tea-cup+xiaolongbao-on-floor/point-off | 珍珠奶茶 | CLIP [1] to box (0.18,0.32 0.30×0.45) | part of [1] (6066 px) | 100% → 100% | 0% → 0% | no → no | 8% | ok |
| bubble-tea-cup+xiaolongbao-on-floor/point-off | 小籠包 | instance 1 | part of [1] (46524 px) | 100% → 100% | 0% → 3% | no → no | 1% | ok |
| bubble-tea-cup+xiaolongbao-on-cafe/tight | 珍珠奶茶 | CLIP [1] to box (0.18,0.32 0.30×0.45) | part of [1] (50445 px), no cut-out | 100% → 0% | 0% → 0% | no → no | 0% | ok |
| bubble-tea-cup+xiaolongbao-on-cafe/tight | 小籠包 | instance 1 | part of [1] (58082 px) | 100% → 100% | 0% → 0% | no → no | 7% | ok |
| bubble-tea-cup+xiaolongbao-on-cafe/loose | 珍珠奶茶 | CLIP [1] to box (0.14,0.26 0.38×0.59) | part of [1] (50921 px), no cut-out | 100% → 0% | 0% → 0% | no → no | 0% | ok |
| bubble-tea-cup+xiaolongbao-on-cafe/loose | 小籠包 | instance 1 | part of [1] (57960 px) | 100% → 100% | 0% → 1% | no → no | 7% | ok |
| bubble-tea-cup+xiaolongbao-on-cafe/small | 珍珠奶茶 | CLIP [1] to box (0.22,0.38 0.22×0.34) | part of [1] (58127 px), no cut-out | 81% → 0% | 100% → 0% | no → no | 0% | ok |
| bubble-tea-cup+xiaolongbao-on-cafe/small | 小籠包 | CLIP [1] to box (0.32,0.45 0.48×0.30) | part of [1] (58015 px) | 82% → 100% | 100% → 0% | no → no | 7% | ok |
| bubble-tea-cup+xiaolongbao-on-cafe/right | 珍珠奶茶 | CLIP [1] to box (0.21,0.32 0.30×0.45) | part of [1] (50777 px), no cut-out | 99% → 0% | 100% → 0% | no → no | 0% | ok |
| bubble-tea-cup+xiaolongbao-on-cafe/right | 小籠包 | CLIP [1] to box (0.32,0.41 0.63×0.39) | part of [1] (57833 px) | 96% → 100% | 100% → 0% | no → no | 7% | ok |
| bubble-tea-cup+xiaolongbao-on-cafe/left | 珍珠奶茶 | CLIP [1] to box (0.15,0.32 0.30×0.45) | part of [1] (50779 px), no cut-out | 100% → 0% | 0% → 0% | no → no | 0% | ok |
| bubble-tea-cup+xiaolongbao-on-cafe/left | 小籠包 | instance 1 | part of [1] (58131 px) | 100% → 100% | 0% → 0% | no → no | 7% | ok |
| bubble-tea-cup+xiaolongbao-on-cafe/down | 珍珠奶茶 | CLIP [1] to box (0.18,0.37 0.30×0.45) | part of [1] (50693 px), no cut-out | 99% → 0% | 0% → 0% | no → no | 0% | ok |
| bubble-tea-cup+xiaolongbao-on-cafe/down | 小籠包 | instance 1 | part of [1] (58084 px) | 100% → 100% | 0% → 0% | no → no | 7% | ok |
| bubble-tea-cup+xiaolongbao-on-cafe/up | 珍珠奶茶 | CLIP [1] to box (0.18,0.27 0.30×0.45) | part of [1] (57524 px), no cut-out | 85% → 0% | 100% → 0% | no → no | 0% | ok |
| bubble-tea-cup+xiaolongbao-on-cafe/up | 小籠包 | instance 1 | part of [1] (58085 px) | 100% → 100% | 0% → 0% | no → no | 7% | ok |
| bubble-tea-cup+xiaolongbao-on-cafe/point-off | 珍珠奶茶 | CLIP [1] to box (0.18,0.32 0.30×0.45) | part of [1] (50445 px), no cut-out | 100% → 0% | 0% → 0% | no → no | 0% | ok |
| bubble-tea-cup+xiaolongbao-on-cafe/point-off | 小籠包 | instance 1 | part of [1] (58082 px) | 100% → 100% | 0% → 0% | no → no | 7% | ok |
| lint-roller+keys-on-floor/tight | 滾筒黏毛器 | CLIP [1] to box (0.14,0.32 0.37×0.45) | part of [1] (10338 px), no cut-out | 100% → 0% | 0% → 0% | no → no | 0% | ok |
| lint-roller+keys-on-floor/tight | 鑰匙 | CLIP [1] to box (0.33,0.41 0.59×0.39) | part of [1] (18884 px) | 100% → 100% | 2% → 2% | no → no | 10% | ok |
| lint-roller+keys-on-floor/loose | 滾筒黏毛器 | CLIP [1] to box (0.09,0.26 0.49×0.59) | part of [1] (7444 px) | 100% → 74% | 0% → 0% | no → no | 0% | FAIL: covers 74% of the thing (< 85%) |
| lint-roller+keys-on-floor/loose | 鑰匙 | instance 1 | part of [1] (21540 px) | 100% → 100% | 2% → 2% | no → no | 10% | ok |
| lint-roller+keys-on-floor/small | 滾筒黏毛器 | CLIP [1] to box (0.19,0.38 0.28×0.34) | part of [1] (11200 px) | 55% → 100% | 85% → 0% | no → no | 5% | ok |
| lint-roller+keys-on-floor/small | 鑰匙 | CLIP [1] to box (0.40,0.45 0.45×0.30) | part of [1] (18082 px) | 95% → 98% | 100% → 44% | no → no | 0% | FAIL: a straight cut through the thing along 44% of a line (column 335 of 900) |
| lint-roller+keys-on-floor/right | 滾筒黏毛器 | CLIP [1] to box (0.18,0.32 0.37×0.45) | part of [1] (21917 px), no cut-out | 95% → 0% | 100% → 0% | no → no | 0% | ok |
| lint-roller+keys-on-floor/right | 鑰匙 | CLIP [1] to box (0.40,0.41 0.59×0.39) | part of [1] (18211 px) | 98% → 99% | 100% → 47% | no → no | 0% | FAIL: a straight cut through the thing along 47% of a line (column 358 of 900) |
| lint-roller+keys-on-floor/left | 滾筒黏毛器 | CLIP [1] to box (0.10,0.32 0.37×0.45) | part of [1] (6560 px) | 96% → 74% | 100% → 4% | no → no | 0% | FAIL: covers 74% of the thing (< 85%) |
| lint-roller+keys-on-floor/left | 鑰匙 | CLIP [1] to box (0.26,0.41 0.59×0.39) | part of [1] (22670 px) | 99% → 100% | 2% → 2% | no → no | 10% | ok |
| lint-roller+keys-on-floor/down | 滾筒黏毛器 | CLIP [1] to box (0.14,0.37 0.37×0.45) | part of [1] (10338 px) | 69% → 100% | 100% → 0% | no → no | 0% | ok |
| lint-roller+keys-on-floor/down | 鑰匙 | CLIP [1] to box (0.33,0.45 0.59×0.39) | part of [1] (18604 px) | 100% → 100% | 2% → 2% | no → no | 0% | ok |
| lint-roller+keys-on-floor/up | 滾筒黏毛器 | CLIP [1] to box (0.14,0.27 0.37×0.45) | part of [1] (10338 px), no cut-out | 96% → 0% | 100% → 0% | no → no | 0% | ok |
| lint-roller+keys-on-floor/up | 鑰匙 | CLIP [1] to box (0.33,0.36 0.59×0.39) | part of [1] (18868 px) | 99% → 100% | 100% → 2% | no → no | 10% | ok |
| lint-roller+keys-on-floor/point-off | 滾筒黏毛器 | CLIP [1] to box (0.14,0.32 0.37×0.45) | part of [1] (10338 px), no cut-out | 100% → 0% | 0% → 0% | no → no | 0% | ok |
| lint-roller+keys-on-floor/point-off | 鑰匙 | CLIP [1] to box (0.33,0.41 0.59×0.39) | part of [1] (18884 px) | 100% → 100% | 2% → 2% | no → no | 10% | ok |
| lint-roller+keys-on-cafe/tight | 滾筒黏毛器 | CLIP [1] to box (0.14,0.32 0.37×0.45) | no mask, no cut-out | 0% → 0% | 0% → 0% | no → no | 0% | ok |
| lint-roller+keys-on-cafe/tight | 鑰匙 | instance 1 | part of [1] (29983 px) | 100% → 100% | 0% → 0% | no → no | 5% | ok |
| lint-roller+keys-on-cafe/loose | 滾筒黏毛器 | CLIP [1] to box (0.09,0.26 0.49×0.59) | no mask, no cut-out | 0% → 0% | 0% → 0% | no → no | 0% | ok |
| lint-roller+keys-on-cafe/loose | 鑰匙 | instance 1 | part of [1] (29983 px) | 100% → 100% | 0% → 0% | no → no | 18% | FAIL: 18% of it is another named thing |
| lint-roller+keys-on-cafe/small | 滾筒黏毛器 | no mask | no mask, no cut-out | 0% → 0% | 0% → 0% | no → no | 0% | ok |
| lint-roller+keys-on-cafe/small | 鑰匙 | instance 1 | instance 1 | 100% → 100% | 0% → 0% | no → no | 0% | ok |
| lint-roller+keys-on-cafe/right | 滾筒黏毛器 | CLIP [1] to box (0.18,0.32 0.37×0.45) | part of [1] (22611 px), no cut-out | 0% → 0% | 0% → 0% | no → no | 0% | ok |
| lint-roller+keys-on-cafe/right | 鑰匙 | instance 1 | part of [1] (29544 px) | 100% → 98% | 0% → 84% | no → no | 0% | FAIL: a straight cut through the thing along 84% of a line (column 332 of 900) |
| lint-roller+keys-on-cafe/left | 滾筒黏毛器 | no mask | no mask, no cut-out | 100% → 0% | 0% → 0% | no → no | 0% | ok |
| lint-roller+keys-on-cafe/left | 鑰匙 | instance 1 | instance 1 | 100% → 100% | 0% → 0% | no → no | 0% | ok |
| lint-roller+keys-on-cafe/down | 滾筒黏毛器 | CLIP [1] to box (0.14,0.37 0.37×0.45) | no mask, no cut-out | 0% → 0% | 0% → 0% | no → no | 0% | ok |
| lint-roller+keys-on-cafe/down | 鑰匙 | instance 1 | part of [1] (29983 px) | 100% → 100% | 0% → 0% | no → no | 6% | ok |
| lint-roller+keys-on-cafe/up | 滾筒黏毛器 | no mask | no mask, no cut-out | 100% → 0% | 0% → 0% | no → no | 0% | ok |
| lint-roller+keys-on-cafe/up | 鑰匙 | instance 1 | instance 1 | 100% → 100% | 0% → 0% | no → no | 0% | ok |
| lint-roller+keys-on-cafe/point-off | 滾筒黏毛器 | CLIP [1] to box (0.14,0.32 0.37×0.45) | no mask, no cut-out | 0% → 0% | 0% → 0% | no → no | 0% | ok |
| lint-roller+keys-on-cafe/point-off | 鑰匙 | instance 1 | part of [1] (29983 px) | 100% → 100% | 0% → 0% | no → no | 5% | ok |
| umbrella+lantern-on-floor/tight | 雨傘 | CLIP [1] to box (0.20,0.32 0.27×0.45) | part of [1] (8596 px) | 100% → 100% | 0% → 0% | no → no | 11% | ok |
| umbrella+lantern-on-floor/tight | 燈籠 | instance 1 | part of [1] (29577 px) | 100% → 100% | 0% → 0% | no → no | 0% | ok |
| umbrella+lantern-on-floor/loose | 雨傘 | CLIP [1] to box (0.16,0.26 0.35×0.59) | no mask, no cut-out | 100% → 0% | 0% → 0% | no → no | 0% | ok |
| umbrella+lantern-on-floor/loose | 燈籠 | instance 1 | part of [1] (36312 px) | 100% → 100% | 0% → 0% | no → no | 16% | FAIL: 16% of it is another named thing |
| umbrella+lantern-on-floor/small | 雨傘 | CLIP [1] to box (0.23,0.38 0.20×0.34) | part of [1] (32976 px), no cut-out | 77% → 0% | 100% → 0% | no → no | 0% | ok |
| umbrella+lantern-on-floor/small | 燈籠 | CLIP [1] to box (0.35,0.45 0.38×0.30) | part of [1] (29248 px) | 86% → 100% | 100% → 28% | no → no | 0% | ok |
| umbrella+lantern-on-floor/right | 雨傘 | CLIP [1] to box (0.23,0.32 0.27×0.45) | part of [1] (32864 px), no cut-out | 97% → 0% | 100% → 0% | no → no | 0% | ok |
| umbrella+lantern-on-floor/right | 燈籠 | CLIP [1] to box (0.34,0.41 0.50×0.39) | part of [1] (29127 px) | 97% → 100% | 100% → 28% | no → no | 0% | ok |
| umbrella+lantern-on-floor/left | 雨傘 | CLIP [1] to box (0.17,0.32 0.27×0.45) | part of [1] (7797 px) | 100% → 100% | 0% → 0% | no → no | 3% | ok |
| umbrella+lantern-on-floor/left | 燈籠 | instance 1 | part of [1] (29859 px) | 100% → 100% | 0% → 0% | no → no | 0% | ok |
| umbrella+lantern-on-floor/down | 雨傘 | CLIP [1] to box (0.20,0.37 0.27×0.45) | part of [1] (9801 px), no cut-out | 94% → 0% | 100% → 0% | no → no | 0% | ok |
| umbrella+lantern-on-floor/down | 燈籠 | CLIP [1] to box (0.29,0.45 0.50×0.39) | part of [1] (29516 px) | 97% → 100% | 100% → 0% | no → no | 0% | ok |
| umbrella+lantern-on-floor/up | 雨傘 | CLIP [1] to box (0.20,0.27 0.27×0.45) | part of [1] (8353 px), no cut-out | 88% → 0% | 100% → 0% | no → no | 0% | ok |
| umbrella+lantern-on-floor/up | 燈籠 | instance 1 | part of [1] (31397 px) | 100% → 100% | 0% → 0% | no → no | 5% | ok |
| umbrella+lantern-on-floor/point-off | 雨傘 | CLIP [1] to box (0.20,0.32 0.27×0.45) | part of [1] (8596 px) | 100% → 100% | 0% → 0% | no → no | 11% | ok |
| umbrella+lantern-on-floor/point-off | 燈籠 | instance 1 | part of [1] (29577 px) | 100% → 100% | 0% → 0% | no → no | 0% | ok |
| umbrella+lantern-on-cafe/tight | 雨傘 | CLIP [1] to box (0.20,0.32 0.27×0.45) | part of [1] (8684 px) | 100% → 100% | 0% → 0% | no → no | 11% | ok |
| umbrella+lantern-on-cafe/tight | 燈籠 | instance 1 | part of [1] (41297 px) | 100% → 100% | 1% → 1% | no → no | 0% | ok |
| umbrella+lantern-on-cafe/loose | 雨傘 | CLIP [1] to box (0.16,0.26 0.35×0.59) | no mask, no cut-out | 100% → 0% | 0% → 0% | no → no | 0% | ok |
| umbrella+lantern-on-cafe/loose | 燈籠 | instance 1 | part of [1] (48011 px) | 100% → 100% | 1% → 0% | no → no | 13% | FAIL: 13% of it is another named thing |
| umbrella+lantern-on-cafe/small | 雨傘 | CLIP [1] to box (0.23,0.38 0.20×0.34) | part of [1] (32974 px), no cut-out | 77% → 0% | 100% → 0% | no → no | 0% | ok |
| umbrella+lantern-on-cafe/small | 燈籠 | CLIP [1] to box (0.35,0.45 0.38×0.30) | part of [1] (40782 px) | 86% → 100% | 100% → 28% | no → no | 0% | ok |
| umbrella+lantern-on-cafe/right | 雨傘 | CLIP [1] to box (0.23,0.32 0.27×0.45) | part of [1] (32837 px), no cut-out | 97% → 0% | 100% → 0% | no → no | 0% | ok |
| umbrella+lantern-on-cafe/right | 燈籠 | CLIP [1] to box (0.34,0.41 0.50×0.39) | part of [1] (40840 px) | 97% → 100% | 100% → 28% | no → no | 0% | ok |
| umbrella+lantern-on-cafe/left | 雨傘 | CLIP [1] to box (0.17,0.32 0.27×0.45) | part of [1] (7811 px) | 100% → 100% | 0% → 0% | no → no | 3% | ok |
| umbrella+lantern-on-cafe/left | 燈籠 | instance 1 | part of [1] (41573 px) | 100% → 100% | 1% → 1% | no → no | 0% | ok |
| umbrella+lantern-on-cafe/down | 雨傘 | CLIP [1] to box (0.20,0.37 0.27×0.45) | part of [1] (9626 px), no cut-out | 94% → 0% | 100% → 0% | no → no | 0% | ok |
| umbrella+lantern-on-cafe/down | 燈籠 | instance 1 | part of [1] (41241 px) | 100% → 100% | 1% → 1% | no → no | 0% | ok |
| umbrella+lantern-on-cafe/up | 雨傘 | CLIP [1] to box (0.20,0.27 0.27×0.45) | part of [1] (8592 px), no cut-out | 88% → 0% | 100% → 0% | no → no | 0% | ok |
| umbrella+lantern-on-cafe/up | 燈籠 | instance 1 | part of [1] (43112 px) | 100% → 100% | 1% → 1% | no → no | 4% | ok |
| umbrella+lantern-on-cafe/point-off | 雨傘 | CLIP [1] to box (0.20,0.32 0.27×0.45) | part of [1] (8684 px) | 100% → 100% | 0% → 0% | no → no | 11% | ok |
| umbrella+lantern-on-cafe/point-off | 燈籠 | instance 1 | part of [1] (41297 px) | 100% → 100% | 1% → 1% | no → no | 0% | ok |
| succulent+juice-on-floor/tight | 多肉植物 | instance 1 | instance 1 | 100% → 100% | 0% → 0% | no → no | 0% | ok |
| succulent+juice-on-floor/tight | 果汁 | instance 2 | instance 2 | 100% → 100% | 0% → 0% | no → no | 0% | ok |
| succulent+juice-on-floor/loose | 多肉植物 | instance 1 | instance 1 | 100% → 100% | 0% → 0% | no → no | 0% | ok |
| succulent+juice-on-floor/loose | 果汁 | instance 2 | instance 2 | 100% → 100% | 0% → 0% | no → no | 0% | ok |
| succulent+juice-on-floor/small | 多肉植物 | instance 1 | instance 1 | 100% → 100% | 0% → 0% | no → no | 0% | ok |
| succulent+juice-on-floor/small | 果汁 | instance 2 | instance 2 | 100% → 100% | 0% → 0% | no → no | 0% | ok |
| succulent+juice-on-floor/right | 多肉植物 | instance 1 | instance 1 | 100% → 100% | 0% → 0% | no → no | 0% | ok |
| succulent+juice-on-floor/right | 果汁 | instance 2 | instance 2 | 100% → 100% | 0% → 0% | no → no | 0% | ok |
| succulent+juice-on-floor/left | 多肉植物 | instance 1 | instance 1 | 100% → 100% | 0% → 0% | no → no | 0% | ok |
| succulent+juice-on-floor/left | 果汁 | instance 2 | instance 2 | 100% → 100% | 0% → 0% | no → no | 0% | ok |
| succulent+juice-on-floor/down | 多肉植物 | instance 1 | instance 1 | 100% → 100% | 0% → 0% | no → no | 0% | ok |
| succulent+juice-on-floor/down | 果汁 | instance 2 | instance 2 | 100% → 100% | 0% → 0% | no → no | 0% | ok |
| succulent+juice-on-floor/up | 多肉植物 | instance 1 | instance 1 | 100% → 100% | 0% → 0% | no → no | 0% | ok |
| succulent+juice-on-floor/up | 果汁 | instance 2 | instance 2 | 100% → 100% | 0% → 0% | no → no | 0% | ok |
| succulent+juice-on-floor/point-off | 多肉植物 | instance 1 | instance 1 | 100% → 100% | 0% → 0% | no → no | 0% | ok |
| succulent+juice-on-floor/point-off | 果汁 | instance 2 | instance 2 | 100% → 100% | 0% → 0% | no → no | 0% | ok |
| succulent+juice-on-cafe/tight | 多肉植物 | CLIP [1] to box (0.08,0.32 0.49×0.45) | part of [1] (47582 px) | 100% → 100% | 0% → 0% | no → no | 0% | ok |
| succulent+juice-on-cafe/tight | 果汁 | CLIP [1] to box (0.56,0.41 0.30×0.39) | part of [1] (32901 px) | 100% → 100% | 0% → 0% | no → no | 0% | ok |
| succulent+juice-on-cafe/loose | 多肉植物 | CLIP [1] to box (0.01,0.26 0.64×0.59) | part of [1] (48513 px) | 100% → 100% | 0% → 0% | no → no | 2% | ok |
| succulent+juice-on-cafe/loose | 果汁 | CLIP [1] to box (0.52,0.35 0.39×0.51) | part of [1] (33014 px), no cut-out | 100% → 0% | 0% → 0% | no → no | 0% | ok |
| succulent+juice-on-cafe/small | 多肉植物 | CLIP [1] to box (0.14,0.38 0.37×0.34) | part of [1] (47855 px) | 87% → 100% | 100% → 0% | no → no | 0% | ok |
| succulent+juice-on-cafe/small | 果汁 | CLIP [1] to box (0.60,0.45 0.23×0.30) | part of [1] (23008 px) | 82% → 100% | 100% → 0% | no → no | 0% | ok |
| succulent+juice-on-cafe/right | 多肉植物 | CLIP [1] to box (0.14,0.32 0.49×0.45) | part of [1] (68385 px) | 98% → 100% | 100% → 0% | no → no | 0% | ok |
| succulent+juice-on-cafe/right | 果汁 | CLIP [1] to box (0.60,0.41 0.30×0.39) | part of [1] (22873 px) | 96% → 100% | 100% → 0% | no → no | 0% | ok |
| succulent+juice-on-cafe/left | 多肉植物 | CLIP [1] to box (0.03,0.32 0.49×0.45) | part of [1] (47311 px) | 98% → 100% | 100% → 0% | no → no | 0% | ok |
| succulent+juice-on-cafe/left | 果汁 | CLIP [1] to box (0.53,0.41 0.30×0.39) | part of [1] (69820 px), no cut-out | 96% → 0% | 100% → 0% | no → no | 0% | ok |
| succulent+juice-on-cafe/down | 多肉植物 | CLIP [1] to box (0.08,0.37 0.49×0.45) | part of [1] (47608 px) | 98% → 100% | 100% → 0% | no → no | 0% | ok |
| succulent+juice-on-cafe/down | 果汁 | CLIP [1] to box (0.56,0.45 0.30×0.39) | part of [1] (32876 px) | 97% → 100% | 100% → 0% | no → no | 0% | ok |
| succulent+juice-on-cafe/up | 多肉植物 | CLIP [1] to box (0.08,0.27 0.49×0.45) | part of [1] (47785 px) | 96% → 100% | 100% → 0% | no → no | 0% | ok |
| succulent+juice-on-cafe/up | 果汁 | CLIP [1] to box (0.56,0.36 0.30×0.39) | part of [1] (23008 px) | 97% → 100% | 100% → 0% | no → no | 0% | ok |
| succulent+juice-on-cafe/point-off | 多肉植物 | CLIP [1] to box (0.08,0.32 0.49×0.45) | part of [1] (47582 px) | 100% → 100% | 0% → 0% | no → no | 0% | ok |
| succulent+juice-on-cafe/point-off | 果汁 | CLIP [1] to box (0.56,0.41 0.30×0.39) | part of [1] (32901 px) | 100% → 100% | 0% → 0% | no → no | 0% | ok |
| stool+pomelo-on-floor/tight | 塑膠椅 | CLIP [1] to box (0.09,0.32 0.49×0.45) | part of [1] (26228 px) | 100% → 100% | 0% → 0% | no → no | 0% | ok |
| stool+pomelo-on-floor/tight | 柚子 | CLIP [1] to box (0.47,0.41 0.48×0.39) | part of [1] (33220 px) | 100% → 100% | 0% → 0% | no → no | 0% | ok |
| stool+pomelo-on-floor/loose | 塑膠椅 | CLIP [1] to box (0.01,0.26 0.63×0.59) | part of [1] (26236 px) | 100% → 100% | 0% → 0% | no → no | 0% | ok |
| stool+pomelo-on-floor/loose | 柚子 | CLIP [1] to box (0.40,0.35 0.60×0.51) | part of [1] (33380 px) | 100% → 100% | 0% → 0% | no → no | 0% | ok |
| stool+pomelo-on-floor/small | 塑膠椅 | CLIP [1] to box (0.14,0.38 0.37×0.34) | part of [1] (59318 px), no cut-out | 83% → 0% | 100% → 0% | no → no | 0% | ok |
| stool+pomelo-on-floor/small | 柚子 | CLIP [1] to box (0.53,0.45 0.37×0.30) | part of [1] (33149 px) | 84% → 100% | 100% → 0% | no → no | 0% | ok |
| stool+pomelo-on-floor/right | 塑膠椅 | CLIP [1] to box (0.14,0.32 0.49×0.45) | part of [1] (59058 px), no cut-out | 96% → 0% | 100% → 0% | no → no | 0% | ok |
| stool+pomelo-on-floor/right | 柚子 | CLIP [1] to box (0.52,0.41 0.48×0.39) | part of [1] (33113 px) | 97% → 100% | 100% → 0% | no → no | 0% | ok |
| stool+pomelo-on-floor/left | 塑膠椅 | CLIP [1] to box (0.03,0.32 0.49×0.45) | part of [1] (26201 px) | 100% → 100% | 0% → 0% | no → no | 0% | ok |
| stool+pomelo-on-floor/left | 柚子 | CLIP [1] to box (0.42,0.41 0.48×0.39) | part of [1] (33319 px) | 97% → 100% | 100% → 0% | no → no | 0% | ok |
| stool+pomelo-on-floor/down | 塑膠椅 | CLIP [1] to box (0.09,0.37 0.49×0.45) | part of [1] (26228 px) | 92% → 100% | 100% → 0% | no → no | 0% | ok |
| stool+pomelo-on-floor/down | 柚子 | CLIP [1] to box (0.47,0.45 0.48×0.39) | part of [1] (33216 px) | 97% → 100% | 100% → 0% | no → no | 0% | ok |
| stool+pomelo-on-floor/up | 塑膠椅 | CLIP [1] to box (0.09,0.27 0.49×0.45) | part of [1] (26223 px) | 98% → 100% | 100% → 0% | no → no | 0% | ok |
| stool+pomelo-on-floor/up | 柚子 | CLIP [1] to box (0.47,0.36 0.48×0.39) | part of [1] (33236 px) | 96% → 100% | 100% → 0% | no → no | 0% | ok |
| stool+pomelo-on-floor/point-off | 塑膠椅 | CLIP [1] to box (0.09,0.32 0.49×0.45) | part of [1] (26228 px) | 100% → 100% | 0% → 0% | no → no | 0% | ok |
| stool+pomelo-on-floor/point-off | 柚子 | CLIP [1] to box (0.47,0.41 0.48×0.39) | part of [1] (33220 px) | 100% → 100% | 0% → 0% | no → no | 0% | ok |
| stool+pomelo-on-cafe/tight | 塑膠椅 | CLIP [1] to box (0.09,0.32 0.49×0.45) | part of [1] (67790 px) | 100% → 100% | 0% → 0% | no → no | 0% | ok |
| stool+pomelo-on-cafe/tight | 柚子 | CLIP [1] to box (0.47,0.41 0.48×0.39) | part of [1] (42374 px) | 100% → 100% | 0% → 0% | no → no | 0% | ok |
| stool+pomelo-on-cafe/loose | 塑膠椅 | CLIP [1] to box (0.01,0.26 0.63×0.59) | part of [1] (67646 px), no cut-out | 100% → 0% | 0% → 0% | no → no | 0% | ok |
| stool+pomelo-on-cafe/loose | 柚子 | CLIP [1] to box (0.40,0.35 0.60×0.51) | part of [1] (42536 px) | 100% → 100% | 0% → 0% | no → no | 0% | ok |
| stool+pomelo-on-cafe/small | 塑膠椅 | CLIP [1] to box (0.14,0.38 0.37×0.34) | part of [1] (68110 px) | 83% → 100% | 100% → 0% | no → no | 0% | ok |
| stool+pomelo-on-cafe/small | 柚子 | CLIP [1] to box (0.53,0.45 0.37×0.30) | part of [1] (42302 px) | 84% → 100% | 100% → 0% | no → no | 0% | ok |
| stool+pomelo-on-cafe/right | 塑膠椅 | CLIP [1] to box (0.14,0.32 0.49×0.45) | part of [1] (67848 px) | 96% → 100% | 100% → 0% | no → no | 0% | ok |
| stool+pomelo-on-cafe/right | 柚子 | CLIP [1] to box (0.52,0.41 0.48×0.39) | part of [1] (42277 px) | 97% → 100% | 100% → 0% | no → no | 0% | ok |
| stool+pomelo-on-cafe/left | 塑膠椅 | CLIP [1] to box (0.03,0.32 0.49×0.45) | part of [1] (67739 px) | 100% → 100% | 0% → 0% | no → no | 0% | ok |
| stool+pomelo-on-cafe/left | 柚子 | CLIP [1] to box (0.42,0.41 0.48×0.39) | part of [1] (42505 px) | 97% → 100% | 100% → 0% | no → no | 0% | ok |
| stool+pomelo-on-cafe/down | 塑膠椅 | CLIP [1] to box (0.09,0.37 0.49×0.45) | part of [1] (67858 px) | 92% → 100% | 100% → 0% | no → no | 0% | ok |
| stool+pomelo-on-cafe/down | 柚子 | CLIP [1] to box (0.47,0.45 0.48×0.39) | part of [1] (42338 px) | 97% → 100% | 100% → 0% | no → no | 0% | ok |
| stool+pomelo-on-cafe/up | 塑膠椅 | CLIP [1] to box (0.09,0.27 0.49×0.45) | part of [1] (67932 px) | 98% → 100% | 100% → 0% | no → no | 0% | ok |
| stool+pomelo-on-cafe/up | 柚子 | CLIP [1] to box (0.47,0.36 0.48×0.39) | part of [1] (42396 px) | 96% → 100% | 100% → 0% | no → no | 0% | ok |
| stool+pomelo-on-cafe/point-off | 塑膠椅 | CLIP [1] to box (0.09,0.32 0.49×0.45) | part of [1] (67790 px) | 100% → 100% | 0% → 0% | no → no | 0% | ok |
| stool+pomelo-on-cafe/point-off | 柚子 | CLIP [1] to box (0.47,0.41 0.48×0.39) | part of [1] (42374 px) | 100% → 100% | 0% → 0% | no → no | 0% | ok |
