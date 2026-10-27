# #136 round 3 test matrix

| WI | Case | Lane | Assertion | Spec |
| --- | --- | --- | --- | --- |
| WI-1 | Direct search D to A to empty to restored item in real CommandWindow | App bundle | InspectorModel.name and session Current Item (L4) | S5 |
| WI-1 | Shared direct-search reconciler updates InspectorModel synchronously | swift-red | Model name after projection (L4) | S5 |
| WI-2 | Collapsed/expanded footer full forward and reverse Tab cycle with Inspector | App bundle | first responder identity, field visibility, query (L3) | S5 |
| WI-2 | Shell first/last focus targets match its dynamic key-view loop | swift-red | responder identities (L4) | S2 |
| WI-2 | Cmd-I preserves selectedRange and inserted text | App bundle | editor range and query output (L1/L3) | S3 |

Adversarial check: callback invocation alone would miss a stale Inspector model; assert the model name. A focus test limited to search and Inspector would miss the sort and sidebar controls; traverse the entire cycle in both directions.
