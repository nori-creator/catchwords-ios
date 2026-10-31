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
| coffee-cup-saucer-spoon | 杯子 | CLIP [1] to box (0.27,0.01 0.41×0.80) | part of [1] (121847 px) | 98% → 98% | 9% → 9% | no → no | 5% | ok |
| coffee-cup-saucer-spoon | 盤子 | instance 1 | part of [1] (86594 px) | - → - | - → - | - → - | - | ok |
| coffee-cup-saucer-spoon | 湯匙 | CLIP [1] to box (0.53,0.14 0.17×0.70) | part of [1] (120957 px) | 100% → 100% | 0% → 0% | no → no | 31% | ok |
| coffee-cup-box-small | 杯子 | instance 1 | instance 1 + region | 98% → 98% | 9% → 9% | no → no | 0% | ok |
| chelsea-fills-frame | 貓 | instance 1 | instance 1 | 99% → 99% | 30% → 30% | no → no | 0% | ok |
| chelsea-box-small | 貓 | instance 1 | instance 1 | 99% → 99% | 30% → 30% | no → no | 0% | ok |
| astronaut-helmet | 安全帽 | CLIP [1] to box (0.52,0.66 0.48×0.34) | part of [1] (43013 px) | 100% → 100% | 2% → 2% | no → no | 0% | ok |
| astronaut-helmet | 太空梭 | no mask | no mask, no cut-out (expected: none — Vision has no instance for the model shuttle in the whole photo, and the crop round its box has only one instance, lying mostly outside the box; the old plan cut that crop instance at the crop's edge (a straight cut along 100% of a line). No cut-out is the honest result.) | 97% → 0% | 100% → 0% | no → no | 0% | ok |
| astronaut-helmet | 太空人 | CLIP [1] to box (0.00,0.00 0.75×1.00) | part of [1] (136781 px) | - → - | - → - | - → - | - | ok |
| cafe-cup-vase | 咖啡 | instance 1 | instance 1 | 100% → 100% | 0% → 0% | no → no | 0% | ok |
| cafe-cup-vase | 花瓶 | no mask | no mask | 98% → 97% | 20% → 20% | no → no | 0% | ok |
| cafe-cup-vase | 花 | no mask | no mask, no cut-out | - → - | - → - | - → - | - | ok |
| cat-and-plant | 貓 | instance 1 | instance 1 | 95% → 95% | 27% → 27% | no → no | 0% | ok |
| cat-and-plant | 植物 | no mask | no mask, no cut-out | - → - | - → - | - → - | - | ok |
| boba-portrait | 珍珠奶茶 | instance 1 | instance 1 | 96% → 96% | 25% → 25% | no → no | 0% | ok |
| glasses-against-bottle | 眼鏡 | CLIP [1] to box (0.16,0.53 0.63×0.30) | part of [1] (5554 px) | 100% → 100% | 0% → 0% | no → no | 0% | ok |
| glasses-against-bottle | 水壺 | CLIP [1] to box (0.62,0.09 0.29×0.78) | part of [1] (23656 px) | 100% → 100% | 0% → 0% | no → no | 0% | ok |
| keys-on-remote | 遙控器 | instance 1 | instance 1 | 100% → 100% | 0% → 0% | no → no | 0% | ok |
| keys-on-remote | 鑰匙 | instance 2 | instance 2 | 100% → 100% | 0% → 0% | no → no | 0% | ok |
