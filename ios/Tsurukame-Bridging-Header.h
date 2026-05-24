// Copyright 2018 David Sansome
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

#ifndef Tsurukame_Bridging_Header_h
#define Tsurukame_Bridging_Header_h

// Many Swift files rely on UIKit being visible without an explicit `import UIKit`. This used to be
// provided transitively by the Haneke / TKMKanaInput headers; import it directly now that those are
// gone.
#import <UIKit/UIKit.h>

#import <WatchConnectivity/WatchConnectivity.h>

#endif /* Tsurukame_Bridging_Header_h */
