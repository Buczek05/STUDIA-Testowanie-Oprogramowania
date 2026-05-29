*** Settings ***
Documentation    Testy dokumentujące znane błędy w zachowaniu API Simple EPC Simulator.
...              Każdy test PRZECHODZI gdy błąd ISTNIEJE i FAILUJE gdy zostanie naprawiony.
...              Służą jako testy regresji — ich zaliczenie oznacza potwierdzenie buga.
Library          RequestsLibrary
Library          Collections
Suite Setup      Create Session    epc    ${BASE_URL}
Test Setup       Reset EPC

*** Variables ***
${BASE_URL}                  http://localhost:8000
${VALID_UE_ID}               ${50}
${DEFAULT_BEARER_ID}         ${9}
${DEDICATED_BEARER_ID}       ${1}
${VALID_MBPS}                ${10}
${VALID_PROTOCOL}            tcp
${OVER_LIMIT_MBPS}           ${10000}
${FIRST_SESSION_SECONDS}     2

*** Test Cases ***
BUG-1 Stop Traffic Zwraca traffic_stopped Gdy Nie Było Aktywnego Transferu
    [Documentation]    Błąd: DELETE /traffic na bearerze bez uruchomionego transferu zwraca
    ...                status traffic_stopped zamiast błędu.
    ...                Poprawne zachowanie: API powinno zwrócić 4xx — nie można zatrzymać
    ...                sesji, która nigdy nie została uruchomiona.
    [Tags]    bug    stop-transfer
    Attach UE ${VALID_UE_ID}
    Stop traffic on UE ${VALID_UE_ID} bearer ${DEFAULT_BEARER_ID}
    Response should incorrectly confirm traffic_stopped

BUG-2 GET Traffic Stats Zwraca 200 Dla Bearera Bez Historii Transferu
    [Documentation]    Błąd: GET /ues/{ue_id}/bearers/{bearer_id}/traffic dla bearera,
    ...                który nigdy nie miał uruchomionego transferu, zwraca 200 z pustymi
    ...                polami (null, 0) zamiast błędu.
    ...                Poprawne zachowanie: API powinno zwrócić 404 — brak danych transferu
    ...                dla tego bearera.
    [Tags]    bug    check-transfer
    Attach UE ${VALID_UE_ID}
    Get traffic stats for UE ${VALID_UE_ID} bearer ${DEFAULT_BEARER_ID}
    Response should return 200 with null protocol and zero bps

BUG-3 GET Traffic Stats Zachowuje Stare Dane Po Zatrzymaniu Transferu
    [Documentation]    Błąd: po zatrzymaniu transferu GET /traffic nadal zwraca historyczne
    ...                wartości protocol i target_bps z poprzedniej sesji.
    ...                Poprawne zachowanie: po zatrzymaniu pola protocol i target_bps powinny
    ...                być zresetowane do null, a tx_bps/rx_bps do 0.
    [Tags]    bug    check-transfer
    Attach UE ${VALID_UE_ID}
    Start traffic on UE ${VALID_UE_ID} bearer ${DEFAULT_BEARER_ID}
    Stop traffic on UE ${VALID_UE_ID} bearer ${DEFAULT_BEARER_ID}
    Get traffic stats for UE ${VALID_UE_ID} bearer ${DEFAULT_BEARER_ID}
    Response should retain stale protocol and target_bps after stop

BUG-4 Attach Z ue_id Ustawionym Na Boolean true Akceptowany Jako UE ID 1
    [Documentation]    Błąd: pole ue_id akceptuje wartość logiczną true, którą Pydantic
    ...                po cichu konwertuje na integer 1 i pomyślnie tworzy UE.
    ...                Poprawne zachowanie: API powinno zwrócić 422 — wartości boolowskie
    ...                nie są poprawnymi identyfikatorami UE.
    [Tags]    bug    attach    validation
    Send attach request with boolean ue_id true
    Response should accept boolean true as ue_id 1

BUG-5 bearer_count W Stats Liczy Aktywne Traffici A Nie Skonfigurowane Bearery
    [Documentation]    Błąd: pole bearer_count w GET /ues/stats zwraca liczbę bearerów
    ...                z aktywnym trafficiem, nie całkowitą liczbę skonfigurowanych bearerów.
    ...                Dla UE posiadającego 2 bearery bez żadnego trafficu bearer_count = 0.
    ...                Poprawne zachowanie: bearer_count powinno zliczać skonfigurowane
    ...                bearery analogicznie do tego jak ue_count zlicza wszystkie UE.
    [Tags]    bug    stats
    Attach UE ${VALID_UE_ID}
    Add bearer ${DEDICATED_BEARER_ID} to UE ${VALID_UE_ID}
    Get aggregated stats
    bearer_count should be zero despite two configured bearers on UE ${VALID_UE_ID}

BUG-8 Usunięcie Bearera Z Aktywnym Trafficiem Zwraca Sukces Bez Ostrzeżenia
    [Documentation]    Błąd: DELETE /ues/{ue_id}/bearers/{bearer_id} na bearerze
    ...                z aktywną sesją transferu zwraca bearer_deleted bez żadnej informacji
    ...                o wymuszonym zakończeniu aktywnego trafficu.
    ...                Poprawne zachowanie: API powinno zwrócić błąd (wymagając uprzedniego
    ...                zatrzymania trafficu) lub potwierdzić zakończenie sesji w odpowiedzi.
    [Tags]    bug    delete-bearer
    Attach UE ${VALID_UE_ID}
    Add bearer ${DEDICATED_BEARER_ID} to UE ${VALID_UE_ID}
    Start traffic on UE ${VALID_UE_ID} bearer ${DEDICATED_BEARER_ID}
    Delete bearer ${DEDICATED_BEARER_ID} from UE ${VALID_UE_ID}
    Response should confirm bearer_deleted despite active traffic

BUG-10 duration Akumuluje Się Pomiędzy Kolejnymi Sesjami Na Tym Samym Bearerze
    [Documentation]    Błąd: pole duration w GET /traffic nie jest resetowane przy ponownym
    ...                uruchomieniu transferu na tym samym bearerze — kumuluje czas ze
    ...                wszystkich poprzednich sesji na tym bearerze.
    ...                Poprawne zachowanie: duration powinno mierzyć czas wyłącznie
    ...                bieżącej sesji, resetując się do 0 przy każdym nowym starcie.
    [Tags]    bug    traffic    stats
    Attach UE ${VALID_UE_ID}
    Run first traffic session for ${FIRST_SESSION_SECONDS}s on UE ${VALID_UE_ID} bearer ${DEFAULT_BEARER_ID}
    Restart traffic on UE ${VALID_UE_ID} bearer ${DEFAULT_BEARER_ID}
    Get traffic stats for UE ${VALID_UE_ID} bearer ${DEFAULT_BEARER_ID}
    duration should exceed ${FIRST_SESSION_SECONDS}s proving accumulation from previous session

BUG-13 Limit 100 Mbps Nie Jest Egzekwowany — Dowolna Wartość Akceptowana
    [Documentation]    Błąd: limit 100 Mbps zdefiniowany w specyfikacji nie jest egzekwowany.
    ...                Mbps=10000 (10 Gbps) jest akceptowane (target_bps=10000000000), podobnie
    ...                jak dowolna inna wartość powyżej limitu — walidacja górnej granicy
    ...                przepustowości jest całkowicie nieobecna lub nieskuteczna.
    ...                Poprawne zachowanie: każda wartość Mbps > 100 powinna być odrzucona.
    ...                Endpoint: POST /ues/{ue_id}/bearers/{bearer_id}/traffic
    ...                Body: {"protocol": "tcp", "Mbps": 10000}
    [Tags]    bug    traffic    validation
    Attach UE ${VALID_UE_ID}
    Start traffic on UE ${VALID_UE_ID} bearer ${DEFAULT_BEARER_ID} with ${OVER_LIMIT_MBPS} Mbps
    Response should accept 10000 Mbps despite the 100 Mbps spec limit

*** Keywords ***
Reset EPC
    [Documentation]    Przywraca symulator do stanu początkowego przed każdym testem.
    POST On Session    epc    /reset

# --- Akcje domenowe ---

Attach UE ${ue_id}
    [Documentation]    Podłącza UE (helper do przygotowania stanu).
    ${body}=    Create Dictionary    ue_id=${ue_id}
    POST On Session    epc    /ues    json=${body}    expected_status=any

Add bearer ${bearer_id} to UE ${ue_id}
    [Documentation]    Dodaje dedykowany bearer do UE (helper do przygotowania stanu).
    ${body}=    Create Dictionary    bearer_id=${bearer_id}
    POST On Session    epc    /ues/${ue_id}/bearers    json=${body}    expected_status=any

Start traffic on UE ${ue_id} bearer ${bearer_id}
    [Documentation]    Uruchamia transfer z domyślnymi parametrami (helper do przygotowania stanu).
    ${body}=    Create Dictionary    protocol=${VALID_PROTOCOL}    Mbps=${VALID_MBPS}
    POST On Session    epc    /ues/${ue_id}/bearers/${bearer_id}/traffic
    ...    json=${body}    expected_status=any

Start traffic on UE ${ue_id} bearer ${bearer_id} with ${mbps} Mbps
    [Documentation]    Uruchamia transfer z podaną wartością Mbps i zapisuje odpowiedź w ${LAST_RESPONSE}.
    ${body}=    Create Dictionary    protocol=${VALID_PROTOCOL}    Mbps=${mbps}
    ${response}=    POST On Session    epc    /ues/${ue_id}/bearers/${bearer_id}/traffic
    ...    json=${body}    expected_status=any
    Set Test Variable    ${LAST_RESPONSE}    ${response}

Stop traffic on UE ${ue_id} bearer ${bearer_id}
    [Documentation]    Zatrzymuje transfer i zapisuje odpowiedź w ${LAST_RESPONSE}.
    ${response}=    DELETE On Session    epc    /ues/${ue_id}/bearers/${bearer_id}/traffic
    ...    expected_status=any
    Set Test Variable    ${LAST_RESPONSE}    ${response}

Get traffic stats for UE ${ue_id} bearer ${bearer_id}
    [Documentation]    Pobiera statystyki per-bearer i zapisuje odpowiedź w ${LAST_RESPONSE}.
    ${response}=    GET On Session    epc    /ues/${ue_id}/bearers/${bearer_id}/traffic
    ...    expected_status=any
    Set Test Variable    ${LAST_RESPONSE}    ${response}

Get aggregated stats
    [Documentation]    Pobiera zagregowane statystyki GET /ues/stats i zapisuje w ${LAST_RESPONSE}.
    ${response}=    GET On Session    epc    /ues/stats    expected_status=any
    Set Test Variable    ${LAST_RESPONSE}    ${response}

Send attach request with boolean ue_id true
    [Documentation]    Wysyła POST /ues z ue_id ustawionym na wartość boolowską true.
    ${body}=    Create Dictionary    ue_id=${True}
    ${response}=    POST On Session    epc    /ues    json=${body}    expected_status=any
    Set Test Variable    ${LAST_RESPONSE}    ${response}

Delete bearer ${bearer_id} from UE ${ue_id}
    [Documentation]    Wysyła DELETE /ues/{ue_id}/bearers/{bearer_id} i zapisuje odpowiedź w ${LAST_RESPONSE}.
    ${response}=    DELETE On Session    epc    /ues/${ue_id}/bearers/${bearer_id}
    ...    expected_status=any
    Set Test Variable    ${LAST_RESPONSE}    ${response}

Run first traffic session for ${seconds}s on UE ${ue_id} bearer ${bearer_id}
    [Documentation]    Uruchamia transfer, odczekuje ${seconds} sekund i zatrzymuje.
    ...                Symuluje zakończoną sesję, po której duration powinno być ~${seconds}s.
    ${body}=    Create Dictionary    protocol=${VALID_PROTOCOL}    Mbps=${VALID_MBPS}
    POST On Session    epc    /ues/${ue_id}/bearers/${bearer_id}/traffic
    ...    json=${body}    expected_status=any
    Sleep    ${seconds}
    DELETE On Session    epc    /ues/${ue_id}/bearers/${bearer_id}/traffic
    ...    expected_status=any

Restart traffic on UE ${ue_id} bearer ${bearer_id}
    [Documentation]    Ponownie uruchamia transfer na tym samym bearerze i odczekuje 1 sekundę.
    ...                Po tym czasie duration powinno wynosić ~1s — jeśli jest wyższe, bug potwierdzony.
    ${body}=    Create Dictionary    protocol=${VALID_PROTOCOL}    Mbps=${VALID_MBPS}
    POST On Session    epc    /ues/${ue_id}/bearers/${bearer_id}/traffic
    ...    json=${body}    expected_status=any
    Sleep    1s

# --- Asercje domenowe ---

Response should incorrectly confirm traffic_stopped
    [Documentation]    Weryfikuje że API zwróciło 200 traffic_stopped mimo braku aktywnej sesji.
    ...                Test PRZECHODZI = bug istnieje. Test FAILUJE = bug naprawiony (API zwraca 4xx).
    Status Should Be              200    ${LAST_RESPONSE}
    Should Be Equal As Strings    ${LAST_RESPONSE.json()}[status]    traffic_stopped

Response should return 200 with null protocol and zero bps
    [Documentation]    Weryfikuje że GET /traffic zwraca 200 z polami null/0 zamiast 404.
    ...                Test PRZECHODZI = bug istnieje. Test FAILUJE = bug naprawiony (API zwraca 404).
    Status Should Be    200    ${LAST_RESPONSE}
    Should Be Equal     ${LAST_RESPONSE.json()}[protocol]      ${None}
    Should Be Equal     ${LAST_RESPONSE.json()}[target_bps]    ${None}
    Should Be Equal As Integers    ${LAST_RESPONSE.json()}[tx_bps]    0

Response should retain stale protocol and target_bps after stop
    [Documentation]    Weryfikuje że protocol i target_bps nie są zerowane po zatrzymaniu.
    ...                Test PRZECHODZI = bug istnieje. Test FAILUJE = bug naprawiony (pola = null).
    Status Should Be    200    ${LAST_RESPONSE}
    Should Not Be Equal    ${LAST_RESPONSE.json()}[protocol]      ${None}
    Should Not Be Equal    ${LAST_RESPONSE.json()}[target_bps]    ${None}

Response should accept boolean true as ue_id 1
    [Documentation]    Weryfikuje że true jest akceptowane jako ue_id=1 (zamiast błędu 422).
    ...                Test PRZECHODZI = bug istnieje. Test FAILUJE = bug naprawiony (API zwraca 422).
    Status Should Be               200    ${LAST_RESPONSE}
    Should Be Equal As Strings     ${LAST_RESPONSE.json()}[status]    attached
    Should Be Equal As Integers    ${LAST_RESPONSE.json()}[ue_id]     1

bearer_count should be zero despite two configured bearers on UE ${ue_id}
    [Documentation]    Weryfikuje że bearer_count=0 mimo 2 skonfigurowanych bearerów.
    ...                Test PRZECHODZI = bug istnieje. Test FAILUJE = bug naprawiony (bearer_count=2).
    Status Should Be               200    ${LAST_RESPONSE}
    Should Be Equal As Integers    ${LAST_RESPONSE.json()}[bearer_count]    0

Response should confirm bearer_deleted despite active traffic
    [Documentation]    Weryfikuje że API zwróciło bearer_deleted bez ostrzeżenia o aktywnej sesji.
    ...                Test PRZECHODZI = bug istnieje. Test FAILUJE = bug naprawiony (API zwraca 4xx lub ostrzeżenie).
    Status Should Be              200    ${LAST_RESPONSE}
    Should Be Equal As Strings    ${LAST_RESPONSE.json()}[status]    bearer_deleted

Response should accept 10000 Mbps despite the 100 Mbps spec limit
    [Documentation]    Weryfikuje że Mbps=10000 jest akceptowane mimo limitu 100 Mbps.
    ...                Test PRZECHODZI = bug istnieje. Test FAILUJE = bug naprawiony (API zwraca 4xx).
    Status Should Be              200    ${LAST_RESPONSE}
    Should Be Equal As Strings    ${LAST_RESPONSE.json()}[status]    traffic_started
    Should Be Equal As Integers   ${LAST_RESPONSE.json()}[target_bps]    10000000000

duration should exceed ${min_seconds}s proving accumulation from previous session
    [Documentation]    Weryfikuje że duration > ${min_seconds}s po zaledwie ~1s drugiej sesji.
    ...                Test PRZECHODZI = bug istnieje (duration skumulowana). Test FAILUJE = bug naprawiony (~1s).
    Status Should Be    200    ${LAST_RESPONSE}
    ${duration}=    Set Variable    ${LAST_RESPONSE.json()}[duration]
    Should Be True    ${duration} > ${min_seconds}
    ...    duration=${duration}s powinna wynosić ~1s po restarcie — bug akumulacji potwierdzony

