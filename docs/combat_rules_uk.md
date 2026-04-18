# Бойовка в проєкті `Gustav 1`

## Призначення документа

Цей документ пояснює бойову систему проєкту у двох площинах:

1. **Як бойовка задумана архітектурно**: які сутності, переходи станів і бойові ролі закладені в коді.
2. **Як вона наразі реально працює в runtime**: який фактичний цикл симуляції, які формули вже використовуються, а які речі поки існують лише як заготовка або напівпідключений шар.

Документ зібрано за кодом у:

- `src/application`
- `src/simulation`
- `src/presentation/battle`
- `src/presentation/ui`

Основні файли, на яких тримається бойовка:

- `src/simulation/core/battle_simulation.gd`
- `src/simulation/systems/brigade_formation_planner_system.gd`
- `src/simulation/systems/regiment_behavior_system.gd`
- `src/simulation/combat/combat_system.gd`
- `src/simulation/entities/regiment.gd`
- `src/simulation/entities/company.gd`
- `src/simulation/behavior/behavior_ruleset.gd`
- `src/simulation/core/battle_scenario_factory.gd`

---

## 1. Що це за бойовка за задумом

### 1.1. Базова ідея

Проєкт задуманий як **тактична battle-sim бойовка ранньомодерного типу**:

- накази видаються **не окремим ротам**, а переважно **бригаді**;
- бригада сама розкладає свої полки по лінії, флангах, резерву й артилерійській підтримці;
- кожен полк має власну поведінку контакту:
  - зближення;
  - розгортання під вогонь;
  - перестрілка;
  - штурм;
  - відхід;
  - відновлення;
- найменша реальна бойова одиниця в поточній симуляції це **`Company`**, не `Regiment` і не `Subunit`;
- бій вирішується через поєднання:
  - **видимості**,
  - **дистанції**,
  - **формації**,
  - **моралі / cohesion / suppression**,
  - **типу війська**,
  - **наказу / fire behavior / combat posture**.

### 1.2. Історичний стиль бойовки

По назвам формацій, ролей і шаблонам складу видно, що система орієнтується не на Napoleonic line infantry у чистому вигляді, а на **перехідний стиль line / pike-and-shot / early modern combined arms**:

- піхота може бути змішаною: мушкетери + пікінерам;
- є окремі стани `MUSKETEER_LINE`, `TERCIA`, `PROTECTED`;
- кавалерія має `CARACOLE`;
- артилерія б’є не по одній цілі, а по коридору попадання;
- квадрат і brace явно заточені під антикавалерійський сценарій.

### 1.3. Головний задумовий цикл

Задум бойовки такий:

1. гравець або AI видає наказ бригаді;
2. наказ або доходить голосом, або несе месенджер;
3. бригада формує стрій і розставляє полки;
4. полки самі вирішують, у якому вони стані контакту;
5. `CombatSystem` рахує вогонь, артилерію, натиск кавалерії та рукопашну;
6. втрати й шок повертаються назад у `Company` і `Regiment`;
7. мораль, suppression, cohesion змінюють наступний такт поведінки.

---

## 2. Що реально відбувається кожен simulation tick

У `BattleSimulation.advance(delta)` порядок зараз такий:

1. Зростає `time_seconds`.
2. Обробляється `command_queue`.
3. Рухаються месенджери.
4. `BrigadeFormationPlannerSystem.tick()` розкладає бригади й полки по слотах.
5. `RegimentBehaviorSystem.tick()` вирішує контактний стан, рух, орієнтацію, бажану формацію та fire behavior.
6. `CombatSystem.tick()` виконує бойове розв’язання:
   - активує тільки релевантні полки;
   - збирає combat frame;
   - шукає контакти;
   - рахує стрілецький вогонь;
   - рахує артилерію;
   - рахує charge;
   - рахує melee;
   - застосовує результати.
7. Далі окремими інтервалами йдуть:
   - AI генералів;
   - видимість;
   - логістика / точки;
   - маркери останнього контакту.

Висновок: **бійка тут не окремий subsystem “поверх” руху, а частина єдиного authorative simulation loop**.

---

## 3. Основні правила бойовки

## 3.1. Командування і доставка наказів

### Як задумано

- Гравець і AI не керують ротами напряму.
- Наказ іде через командну структуру: армія -> бригада -> полки.
- Наказ має реальну доставку:
  - або голосом;
  - або месенджером.

### Як реалізовано зараз

У `BattleController` вибір іде через **полк**, але наказ адресують **бригаді цього полку**.

У `BattleSimulation._process_player_commands()`:

- створюється `SimOrder`;
- якщо HQ командувача досить близько до HQ бригади, наказ **доставляється миттєво голосом**;
- інакше спавниться `Messenger`.

У `BattleSimulation._tick_messengers()`:

- месенджер фізично рухається до HQ бригади;
- може бути перехоплений ворожим полком;
- при доставці наказ застосовується до всієї бригади.

### Що це означає для бою

- Командний лаг є частиною бойовки.
- Наказ можна зірвати перехопленням.
- Полки не живуть “самі по собі”: вони бойово підпорядковані бригадному наказу.

## 3.2. Ролі наказів і політики

Типи наказів (`SimTypes.OrderType`):

- `MOVE`
- `MARCH`
- `ATTACK`
- `DEFEND`
- `PATROL`
- `HOLD`

Ключові order policies:

- `road_column`
  - для `MOVE` / `MARCH` бригада стає в колону;
- `deploy_on_contact`
  - дозволяє раніше розгортатись у бойову формацію при контакті;
- `retreat_on_flank_collapse`
  - полк може автоматично відходити при локальному провалі флангу;
- `hold_reserve`
  - частина полків утримується в резерві.

## 3.3. Побудова бригади

### Як задумано

Бригада не просто має загальну ціль. Вона:

- оцінює загрозу;
- визначає напрям фронту;
- роздає ролі:
  - центр;
  - лівий фланг;
  - правий фланг;
  - резерв;
  - support artillery;
- виставляє полки по позиційних слотах.

### Як реалізовано

`BrigadeFormationPlannerSystem` щотік:

- обчислює anchor бригади;
- визначає objective;
- вибирає planning direction:
  - по path order;
  - по defensive line;
  - по найближчому ворогу;
  - по objective;
- оцінює загрозу на флангах;
- призначає ролі полкам;
- виставляє `current_target_position` кожному полку.

### Особливості

- при `road_column = true` для `MOVE/MARCH` бригада реально шикується колоною;
- для `DEFEND/HOLD` з лінією полки розкладаються вздовж сегмента;
- резерв може зміщуватись у бік threatened flank;
- артилерія ставиться позаду лінії.

### Важлива прогалина

`_is_front_collapsing()` зараз просто повертає `false`, тобто задум “автоматично комітити резерв при колапсі фронту” в коді заявлений, але ще не реалізований.

## 3.4. Видимість і контакт

### Як задумано

Бій має починатися не від абсолютного knowledge, а від видимості:

- полк бачить на певну дистанцію;
- terrain і висота впливають на visibility;
- ворог може бути втрачений з поля зору;
- після втрати лишаються `LastSeenMarker`.

### Як реалізовано

У `BattleSimulation`:

- кожна армія має свій список спостерігачів:
  - полки;
  - HQ;
- для кожного observer будується effective range;
- враховуються:
  - `terrain.visibility_multiplier`;
  - середня висота;
  - path visibility між двома точками;
- detail level ворога:
  - `NONE`
  - `BROAD`
  - `DETAILED`
  - `CLOSE`

### Що реально впливає на бій

- `RegimentBehaviorSystem._get_visible_enemy()` бере тільки **найближчого видимого ворога**;
- якщо видимості нема, полк може втратити target;
- `CombatSystem` також використовує `visibility_between()` при виборі цілей та accuracy.

## 3.5. Engagement states полку

Це один із головних вузлів усієї бойовки.

Стани (`SimTypes.EngagementState`):

- `NO_CONTACT`
- `APPROACH`
- `DEPLOY_FIRE`
- `FIREFIGHT`
- `ASSAULT`
- `DISENGAGE`
- `RECOVER`

### Як задумано

Полк не має одразу “стріляти” чи “бігти в мили”. Він проходить етапи контакту:

- помітив ворога;
- зближається;
- розгортається;
- веде вогонь;
- штурмує;
- відходить;
- збирається після натиску.

### Як реалізовано

У `RegimentBehaviorSystem._resolve_engagement_state()` рішення залежить від:

- видимого ворога;
- дистанції;
- doctrine;
- suppression;
- recent casualties / recent incoming pressure;
- morale;
- cohesion;
- типу війська;
- поточного order type.

Ключова логіка:

- firearm units переважно йдуть через `DEPLOY_FIRE` / `FIREFIGHT`;
- artillery при тиску намагається `DISENGAGE`, а не `ASSAULT`;
- cavalry / shock units можуть одразу перейти в `ASSAULT`;
- якщо тиск завеликий, полк йде в `DISENGAGE`.

### Locking

`_apply_engagement_state_transition()` задає `engagement_hold_until`, щоб полк не “смикався” між станами кожен кадр.

## 3.6. Формації

### Типи формацій

У `FormationModel` є три базові `FormationType`:

- `LINE`
- `COLUMN`
- `SQUARE`

Плюс розширені `RegimentFormationState`:

- `DEFAULT`
- `MARCH_COLUMN`
- `PROTECTED`
- `MUSKETEER_LINE`
- `TERCIA`

### Як задумано

Тип формації й формаційний state мають впливати і на:

- геометрію;
- швидкість;
- fire behavior;
- антикавалерійський захист;
- visual layout.

### Як реалізовано

У `FormationModel`:

- `COLUMN` дає більше швидкості;
- `SQUARE` гальмує;
- fire multiplier теж залежить від формації.

У `RegimentBehaviorSystem._resolve_engagement_formation()`:

- проти кавалерії infantry може перейти в `SQUARE/PROTECTED`;
- firearm infantry при fire contact переважно йде в `LINE`;
- при march наказі полк йде в `COLUMN/MARCH_COLUMN`.

У `Regiment.request_formation_change()`:

- формація змінюється не миттєво;
- виставляється `formation_reform_until`;
- існує cooldown;
- square реформується довше.

### Практичний наслідок

Реформація робить полк вразливішим:

- `get_reform_exposure()` росте на початку реформи;
- вона прямо входить у формули accuracy, melee pressure і charge interaction.

## 3.7. Fire behavior

`SimTypes.RegimentFireBehavior`:

- `NONE`
- `VOLLEY`
- `COUNTERMARCH`
- `CARACOLE`

### Хто що любить

`Regiment.get_preferred_fire_behavior()`:

- artillery -> `VOLLEY`;
- cavalry у колоні -> `CARACOLE`, інакше `VOLLEY`;
- піхота pike-and-shot -> `COUNTERMARCH`;
- інша firearm infantry -> `VOLLEY`.

### Коли structured fire взагалі дозволений

`Regiment.can_use_structured_fire_behavior()` забороняє його, якщо:

- полк у `MARCH`;
- стоїть у колоні;
- проходить реформування.

У square/protected volley дозволений, але не всі режими.

## 3.8. Combat posture і combat order mode

Це вже “бойова мова” для `CombatSystem`.

### `CombatPosture`

- `IDLE`
- `ADVANCING`
- `FIRING`
- `MELEE`
- `CHARGE_WINDUP`
- `CHARGE_COMMIT`
- `CHARGE_RECOVER`
- `RETIRING`

### `CombatOrderMode`

- `NONE`
- `HOLD_FIRE`
- `FIRE_AT_WILL`
- `VOLLEY`
- `COUNTERMARCH`
- `BRACE`
- `CHARGE`

### Як формується

`Regiment.update_combat_intent()` переводить high-level стан полку в runtime-параметри для бою:

- `FIREFIGHT` -> `FIRING`;
- `ASSAULT` для cavalry -> `CHARGE_WINDUP`;
- `ASSAULT` для інших -> `ADVANCING`;
- `DISENGAGE` -> `RETIRING`;
- `PROTECTED/SQUARE` -> `BRACE` або `VOLLEY`.

---

## 4. Реальні бойові правила по сутностях

## 4.1. `Company` як справжня бойова одиниця

У поточній реалізації саме `Company` отримує:

- втрати;
- morale delta;
- cohesion delta;
- suppression delta;
- ammo delta;
- routed flag;
- reload state.

### Базові бойові профілі `Company`

`Company._apply_combat_profile_defaults()` задає профіль за `combat_role`.

#### Musket

- `fire_cycle_duration = 1.0`
- `recover_duration = 0.35`
- `reload_duration = 4.0`
- `melee_reach = 1.0`
- помірний brace / charge resistance

#### Pike

- без reload cycle;
- `melee_reach = 1.8`;
- високий `brace_value`;
- висока `charge_resistance`.

#### Cavalry

- без reload cycle;
- `melee_reach = 1.2`;
- високий `charge_bonus`;
- нижчий brace.

#### Artillery

- `fire_cycle_duration = 1.1`
- `recover_duration = 0.85`
- `reload_duration = 9.0`
- слабкий melee profile.

### Реальні дальності (`Company.get_max_range()`)

- `musket` -> `165`
- `carbine` -> `135`
- `pistol` -> `70`
- `pike` -> `24`
- `cannon` -> `900`

### Ємність активних стрільців і бійців

`get_estimated_active_shooter_capacity()`:

- базово ~22% людей роти вважаються активними стрільцями;
- роль слота може це підсилити або послабити;
- cohesion множить результат.

`get_estimated_active_melee_capacity()`:

- базово ~18%;
- pike ~28%;
- cavalry ~24%;
- artillery ~8%;
- захисні pike-ролі дають бонус.

### Reload loop

`tick_combat_state(delta)`:

- `READY`
- `FIRING`
- `RECOVERING`
- `RELOADING`
- знову `READY`

Для pike / cavalry loop фактично не працює, бо в них fire cycle = 0.

## 4.2. `Regiment` як агрегатор і носій наміру

Полк у цій архітектурі:

- агрегує `Company`;
- несе command/behavior state;
- тримає формацію;
- визначає, як компанії повинні стояти;
- агрегує мораль і боєздатність назад угору.

### Ключові бойові функції `Regiment`

#### Базові агрегати

- `get_total_strength()`
- `get_strength_ratio()`
- `get_attack_range()`
- `has_significant_firearm_capability()`
- `can_commit_assault()`

#### Контактні дистанції

- `get_tactical_contact_distance()`
  - дистанція, на якій полк вважає себе в тактичному контакті;
- `get_close_engagement_distance()`
  - ближча дистанція для assault / melee;
- `get_charge_windup_distance()`
  - довжина підготовки до кавалерійського натиску.

#### Формації і реформа

- `request_formation_change()`
- `_estimate_formation_reform_duration()`
- `is_reforming()`
- `get_reform_exposure()`
- `get_effective_company_reform_speed()`
- `get_effective_banner_reform_speed()`

#### Бойовий стан

- `initialize_regiment_combat_state()`
- `refresh_combat_aggregates()`
- `update_combat_intent()`
- `is_combat_locked()`
- `is_braced()`

#### Візуально-формаційний шар

Величезний блок helper-функцій у `Regiment` відповідає за побудову розкладки компаній:

- `_build_lightweight_*_slot_specs`
- `_build_*_visual_elements`
- `_build_*_countermarch_visual_elements`
- `_build_pike_and_shot_*`
- `_build_cavalry_*`
- `_build_artillery_*`

Це не просто “красивості”: через них формується геометрія company placement, яка потім впливає на бойовий frame.

### Як полк агрегує стан рот

`refresh_combat_aggregates()` рахує weighted average по всіх компаніях:

- morale;
- cohesion;
- ammo ratio.

Тобто реальний шлях такий:

- `CombatSystem` б’є по `Company`;
- `Regiment` лише агрегує стан назад наверх.

## 4.3. `BehaviorDoctrine` і `BehaviorRuleset`

Це шар “як конкретний тип війська любить битися”.

Параметри doctrine включають:

- effective fire range multiplier;
- march/attack speed multipliers;
- reserve offset;
- deploy distance;
- anti-cavalry square distance;
- disengage thresholds;
- confidence threshold для assault;
- withdraw distance;
- recovery duration;
- state hold duration.

### Дефолтні доктрини

#### `default`

- infantry line behavior;
- halt and fire;
- assault як shock mode.

#### `cavalry_mobile`

- менша effective fire range;
- вища мобільність;
- `ADVANCE_BY_FIRE`;
- нижчі thresholds для disengage;
- охочіше йде в assault.

#### `artillery_static`

- великий fire range multiplier;
- обережна поведінка;
- `WITHDRAW` замість shock assault;
- дуже високий assault confidence threshold, тобто майже ніколи не штурмує.

## 4.4. `RegimentBehaviorSystem`

Це мозок контакту полку.

### Найважливіші функції

#### `tick()`

- тикає полки;
- тикає HQ;
- розв’язує overlap між полками.

#### `_apply_order_behavior()`

Головна orchestration-функція. Послідовно:

- дивиться terrain;
- бере doctrine;
- оновлює recent engagement metrics;
- знаходить видимого ворога;
- вибирає engagement target;
- визначає engagement state;
- просить бажану формацію;
- визначає fire behavior;
- будує movement plan;
- оновлює front_direction;
- рухає полк.

#### `_update_recent_engagement_metrics()`

Обчислює:

- recent casualty rate;
- recent incoming pressure;
- recent effective losses.

Ці значення потім прямо впливають на disengage logic.

#### `_resolve_engagement_target()`

- може триматись за стару ціль;
- не скаче миттєво на ближчого ворога;
- має cooldown на retarget.

#### `_resolve_engagement_state()`

Найважливіша тактична логіка:

- firearm unit зупиняється для fire contact;
- shock unit намагається закрити дистанцію;
- artillery при сильному тиску виходить із контакту;
- static defend/hold не обов’язково сам іде вперед.

#### `_resolve_engagement_formation()`

Визначає, чи полк має:

- перейти в лінію;
- піти в column;
- піти в square/protected;
- лишитись у своєму attack formation.

#### `_resolve_engagement_fire_behavior()`

Дає:

- `VOLLEY`
- `COUNTERMARCH`
- `CARACOLE`
- або `NONE`

залежно від state, формації та типу полку.

#### `_resolve_movement_plan()`

Дає:

- куди рухатись;
- чи рухатись взагалі;
- з яким speed multiplier.

#### `_build_contact_goal()`

Дуже важлива функція.

Вона не жене полк просто в центр ворога. Вона:

- визначає enemy front;
- обчислює lane offset;
- підбирає бажаний spacing;
- розводить дружні полки по фронту однієї ворожої цілі.

#### `_resolve_contact_lane_offset()`

Це механіка “кілька дружніх полків не налазять один на одного при атаці одного й того ж ворога”.

#### `_should_disengage_from_pressure()`

Полк може відійти за:

- suppression;
- casualty rate;
- effective losses;
- низьку morale;
- низьку cohesion.

#### `_resolve_regiment_overlap()`

Система фізичної розшивки полків:

- friendly vs friendly;
- enemy vs enemy;
- у прямому контакті;
- поза прямим контактом.

Це важливо, бо бійка тут опирається на просторову геометрію.

## 4.5. `CombatTypes`

Службовий файл, але він задає vocabulary всієї бойовки:

- `CombatPosture`
- `CombatOrderMode`
- `CombatRole`
- `ReloadState`
- `ContactSide`

Плюс factory-методи:

- `build_empty_frame()`
- `build_empty_outcome_buffer()`
- `build_company_outcome_entry()`
- `build_regiment_outcome_entry()`

Саме через ці структури `CombatSystem` передає результати бою назад у симуляцію.

## 4.6. `CombatSystem`

Це серце фактичного бойового resolution.

### Архітектурно

`CombatSystem.tick()` робить:

1. визначає активні полки;
2. синхронізує їхній live combat state;
3. будує `combat frame`;
4. будує contact candidates;
5. рахує small arms;
6. рахує artillery;
7. рахує charge;
8. рахує melee;
9. застосовує outcomes.

### 4.6.1. Активні полки

`_get_active_regiment_ids()` відсікає весь світ і тримає в активній бойовій симуляції лише тих, хто:

- уже в контакті;
- locked;
- recovering / retreating;
- бачить ворога поруч;
- має pending reload / suppression / visual fire;
- недавно був біля ворога.

Це явний performance-oriented broadphase.

### 4.6.2. Combat frame

`_build_combat_frame()` збирає:

- `regiment_frames`
- `company_frames`
- `sprite_frames`

`company_frame` містить:

- геометрію;
- morale / cohesion / suppression;
- ammo / reload;
- active shooter/melee capacity;
- brace / charge values;
- max range / firepower;
- current engagement/combat state;
- reform exposure;
- routed flag.

### 4.6.3. Контакти

`_build_contact_candidates()`:

- бере sprite-level bodies;
- кладе їх у broadphase grid;
- перевіряє лише сусідні клітинки;
- створює edge між ворожими sprite bodies.

`_build_sprite_contact()` рахує:

- дистанцію;
- shared frontage;
- з якого боку прийшов контакт:
  - front;
  - flank;
  - rear;
- чи може це бути charge impact;
- чи це melee candidate.

### 4.6.4. Small arms

Основний пайплайн:

- `_resolve_small_arms()`
- `_select_small_arms_target_company()`
- `_compute_small_arms_accuracy()`

#### Як стрілецька стрільба реально працює

1. Стріляють тільки `MUSKET`-роти.
2. У роти має бути:
   - правильний `combat_order_mode`;
   - `can_fire_small_arms = true`;
   - ammo;
   - `reload_state = READY`;
   - не `is_routed`.
3. Береться `active_shooter_capacity`.
4. Вибирається найкраща ворожа company.
5. Кількість sample shots:
   - `ceil(active_shooters / 8)`,
   - обмежено `1..12`.
6. Для кожного sample кидається deterministic roll через `_stable_noise_from_key()`.
7. Влучання дає 1 casualty, іноді 2.

#### Від чого залежить accuracy

`_compute_small_arms_accuracy()` враховує:

- range;
- visibility;
- щільність і cohesion цілі;
- exposure цілі;
- morale / cohesion стрільця;
- suppression стрільця;
- чи стрілець рухається;
- training;
- reform exposure стрільця.

#### Що накладає стрільба на ціль

- casualties;
- morale penalty;
- cohesion penalty;
- suppression growth.

#### Що накладає стрільба на стрільця

- ammo loss;
- `reload_state = FIRING`;
- `reload_progress = 0`.

### 4.6.5. Артилерія

Основний пайплайн:

- `_resolve_artillery()`
- `_select_artillery_target()`
- `_build_artillery_aim_solution()`
- `_collect_artillery_corridor_hits()`
- `_compute_artillery_casualties()`

#### Як вона реально працює

1. Стріляють тільки `ARTILLERY`-company.
2. Вибирається target company у межах range і visibility.
3. Будується aim solution:
   - напрям пострілу;
   - латеральна похибка;
   - похибка по дальності;
   - corridor length;
   - lane width;
   - projectile energy.
4. Потім не одна ціль “отримує снаряд”, а збираються всі sprite bodies, які лежать у коридорі проходження roundshot.
5. Energy зменшується після кожного хіта.

#### Від чого залежить артилерійська точність

- дистанція;
- видимість;
- morale;
- cohesion;
- suppression;
- training;
- density / reform exposure цілі;
- reform exposure стрільця.

#### Наслідок

Артилерія тут моделюється як **line-sweeping fire through a corridor**, а не як один дискретний hit-scan shot.

### 4.6.6. Charge

Основний пайплайн:

- `_resolve_charge()`
- `_resolve_charge_edge()`

#### Як задумано

Кавалерія в `ASSAULT` має входити в `CHARGE_WINDUP`, ударяти в ціль, після чого:

- або пробивати фронт;
- або відскакувати;
- або входити в melee / recover / retreat.

#### Що реально вже є

Charge працює тільки коли:

- контакт є;
- одна сторона cavalry, інша ні;
- attacker має `combat_order_mode = CHARGE`;
- attacker має `combat_posture = CHARGE_WINDUP`;
- attacker не recovering;
- обидві роти не routed.

`_resolve_charge_edge()` рахує:

- impact strength атакуючого;
- brace захисника;
- pike-wall bonus;
- bonus за flank/rear.

Можливі результати:

- charge repulsed;
- charge hit;
- обидві сторони примусово переводяться в `MELEE`;
- ставиться `combat_lock_until`.

#### Важливе обмеження поточної реалізації

Хоча структура підтримує:

- `CHARGE_COMMIT`
- `charge_recovery_until`
- `charge_retreat_until`
- `charge_stage_position`
- `charge_target_company_id`

у поточному коді **реальний запис recovery / retreat outcome майже не використовується**. Тобто каркас для більш повного charge-loop є, але runtime ще зведений до “impact -> casualties -> melee lock”.

### 4.6.7. Melee

Основний пайплайн:

- `_resolve_melee()`
- `_resolve_melee_edge()`
- `_compute_melee_pressure()`
- `_compute_melee_casualties()`
- `_should_break_in_melee()`

#### Як реально працює melee

1. Беруться contact edges.
2. Сортуються за shared frontage.
3. Один sprite не може бути задіяний у кількох melee одночасно.
4. Charge-contact окремо пропускається, щоб не double count.
5. Для обох сторін рахується pressure.
6. За pressure визначаються:
   - losses;
   - morale loss;
   - cohesion loss;
   - suppression gain;
   - можливий break / route.

#### Що входить у pressure

- active melee capacity;
- shared frontage;
- morale;
- cohesion;
- training;
- suppression;
- role matchup;
- flank / rear bonus;
- reform exposure.

#### Спеціальні matchup rules

`_get_melee_role_matchup_multiplier()` дає явні matchup-модифікатори:

- pike сильніші проти cavalry фронтально;
- cavalry слабша проти braced pike фронтом;
- musket кращий проти artillery;
- rear/flank мають бонус.

### 4.6.8. Застосування результатів

`_apply_outcomes()`:

- спочатку розмазує regiment-level deltas по companies;
- потім застосовує company losses;
- оновлює morale/cohesion/suppression/ammo;
- ставить reload overrides;
- ставить routed/destroyed;
- потім застосовує regiment-level posture/brace/locks;
- після цього робить `refresh_combat_aggregates()`.

Важливо: **спершу б’ються компанії, потім полк агрегується назад**, а не навпаки.

---

## 5. По класах і функціях

Нижче стислий map важливих класів і функцій.

## 5.1. `BattleController`

Роль: гравецький ввід і маршрутизація наказів у simulation server.

Ключові функції:

- `_ready()`
  - піднімає `SimulationServer`, `BattlefieldView`, `BattleHUD`, камеру;
- `_unhandled_input()`
  - selection і order gestures;
- `_handle_order_click()`
  - двоклікове задання лінії/маршруту;
- `_issue_pending_order()`
  - формує payload для `submit_player_command()`;
- `_on_snapshot_ready()`
  - оновлює latest snapshot і UI;
- `_get_selected_brigade_hq_position()`
  - всі накази зав’язані на бригадний HQ.

Факт поточної реалізації:

- гравець вибирає полк, але наказує бригаді;
- pre-battle editor існує, але у `_ready()` одразу вимикається й симуляція стартує unpaused.

## 5.2. `SimulationServer`

Роль: server-authoritative boundary між UI і симуляцією.

Ключові функції:

- `configure()`
  - ставить симуляцію;
- `submit_player_command()`
  - відправляє команду в `BattleSimulation`;
- `_physics_process()`
  - окремо тикає sim і окремо віддає snapshot;
- `_build_client_snapshot()`
  - будує snapshot для армії гравця;
- `_build_units_channel_delta()`
  - шле delta-update, а не весь світ щоразу;
- battle log helpers
  - пишуть runtime log бою в `battle_logs/`.

## 5.3. `BattleSimulation`

Роль: authoritative state всього бою.

Ключові функції:

- `advance(delta)`
  - головний simulation loop;
- `_process_player_commands()`
  - створює й запускає orders;
- `_apply_delivered_order()`
  - переносить order state на brigade + regiments;
- `_tick_messengers()`
  - моделює доставку наказів;
- `build_snapshot_for_army()`
  - будує видиму картину світу;
- `_build_regiment_snapshot()`
  - серіалізує стан полку;
- `_update_visibility()`
  - fog/intel loop;
- `_visibility_between()`
  - видимість уздовж шляху;
- `_tick_strategic_points()`
  - victory points;
- `_tick_supply_convoys()`
  - логістичний прототип.

## 5.4. `BrigadeFormationPlannerSystem`

Роль: позиційно розкладає бригаду по фронту.

Ключові функції:

- `tick()`
- `_plan_brigade()`
- `_assign_regiment_roles()`
- `_apply_regiment_slots()`
- `_assign_column_slots()`
- `_assign_line_order_slots()`
- `_assign_role_based_line_slots()`
- `_assign_support_slots()`
- `_get_desired_reserve_count()`
- `_should_commit_reserve()`
- `_update_brigade_threat_assessment()`

## 5.5. `RegimentBehaviorSystem`

Роль: tactical brain окремого полку.

Ключові функції:

- `tick()`
- `_apply_order_behavior()`
- `_resolve_engagement_target()`
- `_resolve_engagement_state()`
- `_apply_engagement_state_transition()`
- `_resolve_engagement_formation()`
- `_resolve_engagement_fire_behavior()`
- `_resolve_movement_plan()`
- `_build_contact_goal()`
- `_resolve_contact_lane_offset()`
- `_should_disengage_from_pressure()`
- `_resolve_regiment_overlap()`

## 5.6. `Regiment`

Роль: tactical container полку.

Ключові функції:

- `initialize_regiment_combat_state()`
- `refresh_combat_aggregates()`
- `update_combat_intent()`
- `request_formation_change()`
- `get_tactical_contact_distance()`
- `get_close_engagement_distance()`
- `can_use_structured_fire_behavior()`
- `update_subunit_blocks()`
- `build_company_visual_layout()`

Сімейства helper-функцій:

- `_build_lightweight_*_slot_specs`
- `_build_*_visual_elements`
- `_build_*_countermarch_visual_elements`
- `_build_pike_and_shot_*`
- `_build_cavalry_*`
- `_build_artillery_*`

## 5.7. `Company`

Роль: actual casualty-bearing combat entity.

Ключові функції:

- `initialize_combat_state()`
- `_apply_combat_profile_defaults()`
- `tick_combat_state()`
- `can_fire_small_arms()`
- `can_fire_artillery()`
- `get_estimated_active_shooter_capacity()`
- `get_estimated_active_melee_capacity()`
- `get_reload_ratio()`

## 5.8. `CombatSystem`

Роль: runtime combat resolver.

Ключові функції:

- `tick()`
- `_get_active_regiment_ids()`
- `_build_combat_frame()`
- `_build_contact_candidates()`
- `_resolve_small_arms()`
- `_resolve_artillery()`
- `_resolve_charge()`
- `_resolve_melee()`
- `_apply_outcomes()`

Найважливіші формульні helper-и:

- `_compute_small_arms_accuracy()`
- `_score_small_arms_target()`
- `_compute_artillery_accuracy()`
- `_score_artillery_target()`
- `_compute_artillery_casualties()`
- `_compute_melee_pressure()`
- `_get_melee_role_matchup_multiplier()`
- `_compute_melee_casualties()`
- `_should_break_in_melee()`

## 5.9. `BattleScenarioFactory`

Роль: задає бойові стартові пакети.

Ключові функції:

- `create_phase_one_battle()`
- `create_large_test_battle()`
- `_create_terrain()`
- `_create_large_terrain()`
- `_create_armies()`
- `_create_large_armies()`
- `_create_regiment()`
- `_create_companies_for_category()`

З цього видно поточний задум за складом:

- звичайна infantry за замовчуванням = 2 musket + 2 pike company;
- cavalry = 4 squadron mix carbine/pistol;
- artillery = 4 battery sections;
- є окремий спеціальний шаблон tercio на 8 company.

---

## 6. Що вже працює добре, а що ще прототипне

## 6.1. Вже реально працює

- бригадні накази;
- затримка доведення наказу через месенджер;
- AI, який видає бригадні накази;
- розкладка полків по ролях;
- engagement state machine;
- automatic reform requests;
- volley / countermarch / caracole як fire behaviors;
- стрілецький вогонь;
- artillery corridor fire;
- melee pressure і role matchups;
- flank/rear bonuses;
- morale / cohesion / suppression economy;
- visibility/fog/intel detail;
- strategic points і victory point accrual.

## 6.2. Частково реалізовано або недороблено

- charge system
  - є impact і переведення в melee, але recovery/retreat loop майже не дописаний;
- reserve collapse logic
  - `_is_front_collapsing()` поки заглушка;
- logistics
  - convoys існують, але `_maybe_spawn_convoys()` порожня;
- army summaries
  - `_update_army_summaries()` порожня;
- defense bonus terrain
  - є в даних, але в бойові формули зараз не входить;
- HQ ammo/supply
  - є в моделі й UI, але не підживлює ammo рот назад у бій.

## 6.3. Явні заготовки / неактивні елементи

- `CombatOrderMode.HOLD_FIRE`
  - оголошений, але в поточній бойовій логіці фактично не використовується;
- `CombatPosture.CHARGE_COMMIT`
  - присутній в enum, але повноцінний runtime-сценарій не розгорнутий;
- `prepare_charge_run()` / `charge_stage_position` / `charge_target_company_id`
  - каркас існує, активного використання майже нема;
- `Subunit`
  - клас існує окремо, але поточна бойова симуляція реально працює через `Company`.

## 6.4. Важливий практичний висновок

Поточна бойовка вже не є “порожнім прототипом”. Вона має повноцінний бойовий цикл і багато реальних чисельних правил. Але це ще **не фінальна цілісна система**:

- command-and-control уже продуманий;
- contact state machine уже сильна;
- ranged / artillery / melee вже досить предметні;
- а от deeper charge phase, terrain defense, logistics-driven resupply і частина резервної логіки ще не доведені до кінця.

---

## 7. Довідка по ключових числах

### 7.1. Командування

- `Commander.command_voice_radius = 175`
- `Messenger.speed = 110`
- `Messenger.delivery_radius = 18`

Практичний сенс:

- якщо HQ командира і HQ бригади в межах 175, наказ миттєвий;
- інакше з’являється месенджер.

### 7.2. Видимість полків

Базові `Regiment.get_vision_range()`:

- infantry -> `200`
- cavalry -> `230`
- artillery -> `210`

Потім це множиться на `lerpf(0.75, 1.1, commander_quality)`.

### 7.3. Базові геометрії формацій

`FormationModel.set_type()`:

- `LINE`
  - frontage `116`
  - depth `70`
  - speed multiplier `1.0`
- `COLUMN`
  - frontage `62`
  - depth `136`
  - speed multiplier `1.15`
- `SQUARE`
  - frontage `98`
  - depth `98`
  - speed multiplier `0.72`

### 7.4. Контактні дистанції полку

`Regiment.get_tactical_contact_distance()` базово:

- infantry -> `92`
- cavalry -> `118`
- artillery -> `140`

Але далі:

- дистанція зростає від attack range;
- додається поправка на власний і ворожий розмір фронту;
- фінально clamp у межах `72..196`.

`Regiment.get_close_engagement_distance()` базово:

- infantry -> `60`
- cavalry -> `78`
- artillery -> `88`

Фінально clamp у межах `52..126`.

### 7.5. Ініціалізація моралі та cohesion

`Regiment.initialize_regiment_combat_state()`:

- `morale = 0.56 + commander_quality * 0.34`
- `cohesion = 0.54 + commander_quality * 0.34`

`Company.initialize_combat_state()`:

- `morale = 0.58 + training * 0.34`
- `cohesion = 0.52 + training * 0.38`

Усе clamp до `0..1`.

### 7.6. Fire / reload числа рот

#### Musket

- range `165`
- fire cycle `1.0`
- recover `0.35`
- reload `4.0`

#### Carbine

- range `135`
- використовує cavalry combat role

#### Pistol

- range `70`
- використовує cavalry combat role

#### Pike

- range `24`
- без reload cycle
- melee reach `1.8`

#### Cannon

- range `900`
- fire cycle `1.1`
- recover `0.85`
- reload `9.0`

### 7.7. Орієнтовні doctrine-пороги

#### `default`

- `fire_hold_distance_ratio = 0.92`
- `assault_distance_ratio = 1.12`
- `disengage_suppression_threshold = 0.48`
- `disengage_casualty_rate_threshold = 0.08`
- `assault_confidence_threshold = 0.7`

#### `cavalry_mobile`

- `fire_hold_distance_ratio = 0.86`
- `assault_distance_ratio = 1.3`
- `disengage_suppression_threshold = 0.34`
- `disengage_casualty_rate_threshold = 0.06`
- `assault_confidence_threshold = 0.6`

#### `artillery_static`

- `fire_hold_distance_ratio = 0.98`
- `assault_distance_ratio = 0.9`
- `disengage_suppression_threshold = 0.28`
- `disengage_casualty_rate_threshold = 0.04`
- `assault_confidence_threshold = 0.95`

## 8. Короткий підсумок в одному абзаці

`Gustav 1` зараз реалізує бойовку як **authoritative brigade-level early-modern tactics sim**, де накази йдуть через командну структуру, бригада сама будує фронт, полки проходять state machine контакту, а фактичний бій вирішується на рівні `Company` через видимість, формацію, стрілецький вогонь, артилерійський коридор, charge impact і melee pressure. Найсильніше вже зроблені: orders, brigade planning, engagement states, fire resolution і melee. Найбільші незавершені шматки: повний charge lifecycle, реальне використання terrain defense, логістичне підживлення бою та кілька системних заглушок навколо резервів і summary-економіки.
