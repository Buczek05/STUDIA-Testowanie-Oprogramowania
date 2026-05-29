*** Settings ***
Documentation    Testy funkcjonalności - sprawdzenie aktualnego transferu (check transfer).
...              - Można sprawdzić transfer dla pojedynczego bearera w ramach UE LUB sumaryczny dla wszystkich jego bearerów
...              - Procedura wymaga podania UE ID oraz opcjonalnych bearer ID oraz unit
...              - Domyślną jednostką jest kbps
Library          RequestsLibrary
Library          Collections
Suite Setup      Create Session    epc    ${BASE_URL}
Test Setup       Reset EPC

*** Variables ***
${BASE_URL}              http://localhost:8000
${VALID_UE_ID}           ${50}
${DEFAULT_BEARER_ID}     ${9}
${INACTIVE_BEARER_ID}    ${5}
${UNATTACHED_UE_ID}      ${77}
${VALID_MBPS}            ${50}
${VALID_PROTOCOL}        tcp
${DEDICATED_BEARER_ID}   ${1}

*** Test Cases ***
T-021 Checking per-bearer traffic of an active transfer returns its stats
    [Documentation]    Akcja: sprawdzenie transferu pojedynczego, aktywnego bearera w ramach UE.
    ...                Oczekiwane: 200 ze statystykami transferu dla podanego UE i bearera (ue_id, bearer_id, protocol, target_bps, tx/rx, duration).
    [Tags]    check-transfer    happy-path
    Attach UE ${VALID_UE_ID}
    Start traffic on UE ${VALID_UE_ID} bearer ${DEFAULT_BEARER_ID}
    Get traffic of UE ${VALID_UE_ID} bearer ${DEFAULT_BEARER_ID}
    Traffic stats should report UE ${VALID_UE_ID} bearer ${DEFAULT_BEARER_ID}

T-022 Checking aggregated traffic for all UEs reports scope all
    [Documentation]    Akcja: sprawdzenie sumarycznego transferu dla wszystkich UE (bez podania UE ID).
    ...                Oczekiwane: 200 ze statystykami o zasięgu "all", zawierającymi liczbę UE, liczbę bearerów oraz sumaryczne tx/rx.
    [Tags]    check-transfer    stats
    Attach UE ${VALID_UE_ID}
    Start traffic on UE ${VALID_UE_ID} bearer ${DEFAULT_BEARER_ID}
    Get aggregated stats for all UEs
    Aggregated stats scope should be all

T-023 Checking aggregated traffic for a single UE reports its scope
    [Documentation]    Akcja: sprawdzenie sumarycznego transferu dla pojedynczego UE (z podaniem UE ID).
    ...                Oczekiwane: 200 ze statystykami o zasięgu "ue:50" obejmującymi wszystkie bearery tego UE.
    [Tags]    check-transfer    stats
    Attach UE ${VALID_UE_ID}
    Start traffic on UE ${VALID_UE_ID} bearer ${DEFAULT_BEARER_ID}
    Get aggregated stats for UE ${VALID_UE_ID}
    Aggregated stats scope should be ue:${VALID_UE_ID}

T-024 Checking aggregated traffic with details returns per-bearer breakdown
    [Documentation]    Akcja: sprawdzenie sumarycznego transferu dla UE z włączonym include_details.
    ...                Oczekiwane: 200 ze statystykami o zasięgu "ue:50" oraz wypełnionym polem details z rozbiciem na bearery UE.
    [Tags]    check-transfer    stats
    Attach UE ${VALID_UE_ID}
    Start traffic on UE ${VALID_UE_ID} bearer ${DEFAULT_BEARER_ID}
    Get aggregated stats with details for UE ${VALID_UE_ID}
    Aggregated stats scope should be ue:${VALID_UE_ID}
    Aggregated stats details should contain UE ${VALID_UE_ID} bearer ${DEFAULT_BEARER_ID}

T-025 Checking aggregated traffic for an unattached UE is rejected
    [Documentation]    Akcja: sprawdzenie sumarycznego transferu dla UE, który nie został przyłączony do sieci.
    ...                Oczekiwane: błąd - procedura wg spec wymaga istniejącego UE ID.
    [Tags]    check-transfer    error
    Getting aggregated stats for UE ${UNATTACHED_UE_ID} should be rejected with message "UE not found"

T-026 Checking per-bearer traffic of an unattached UE is rejected
    [Documentation]    Akcja: sprawdzenie transferu bearera dla UE, który nie został przyłączony do sieci.
    ...                Oczekiwane: błąd - procedura wg spec wymaga istniejącego UE ID.
    [Tags]    check-transfer    error
    Getting traffic of UE ${UNATTACHED_UE_ID} bearer ${DEFAULT_BEARER_ID} should be rejected with message "UE not found"

T-027 Checking aggregated traffic with default unit returns values in kbps
    [Documentation]    Akcja: sprawdzenie sumarycznego transferu dla UE z jednostką kbps (unit=kbps).
    ...                Oczekiwane: wg spec domyślną jednostką jest kbps, więc odpowiedź powinna raportować wartości transferu w kbps.
    [Tags]    check-transfer    unit
    Attach UE ${VALID_UE_ID}
    Start traffic on UE ${VALID_UE_ID} bearer ${DEFAULT_BEARER_ID}
    Get aggregated stats for UE ${VALID_UE_ID} in unit kbps
    Aggregated stats should report values in unit kbps

T-028 Checking traffic of a single inactive bearer is rejected
    [Documentation]    Akcja: sprawdzenie transferu pojedynczego bearera, który nigdy nie został ustanowiony dla UE.
    ...                Oczekiwane: błąd - wg spec transfer dotyczy bearera w ramach UE, więc nieaktywny bearer powinien zostać odrzucony.
    [Tags]    check-transfer    bearer    error
    Attach UE ${VALID_UE_ID}
    Getting traffic of UE ${VALID_UE_ID} bearer ${INACTIVE_BEARER_ID} should be rejected

T-029 Checking traffic of an existing bearer with no transfer history is rejected
    [Documentation]    Akcja: sprawdzenie statystyk transferu bearera 9, który istnieje (tworzony
    ...                automatycznie przy attach), ale nigdy nie miał uruchomionej sesji transferu.
    ...                Oczekiwane: błąd - brak historii transferu powinien skutkować 404.
    [Tags]    check-transfer    bearer    error
    Attach UE ${VALID_UE_ID}
    Getting traffic of UE ${VALID_UE_ID} bearer ${DEFAULT_BEARER_ID} should be rejected

T-078 Aggregated stats bearer_count reflects all configured bearers not only active transfers
    [Documentation]    Akcja: podłączenie UE (bearer 9 tworzony automatycznie) i dodanie dedykowanego
    ...                bearera, następnie sprawdzenie GET /ues/stats bez uruchamiania transferu.
    ...                Oczekiwane: bearer_count = 2 — pole powinno zliczać skonfigurowane bearery,
    ...                nie aktywne sesje transferu.
    [Tags]    check-transfer    stats
    Attach UE ${VALID_UE_ID}
    Add bearer ${DEDICATED_BEARER_ID} to UE ${VALID_UE_ID}
    Get aggregated stats for all UEs
    Aggregated stats bearer_count should be    2

T-079 Duration resets to zero when traffic is restarted on the same bearer
    [Documentation]    Akcja: uruchomienie transferu, odczekanie 2 sekund, zatrzymanie, ponowne
    ...                uruchomienie na tym samym bearerze, odczekanie 1 sekundy, sprawdzenie duration.
    ...                Oczekiwane: duration < 2s — pole powinno być resetowane przy każdym nowym starcie,
    ...                mierząc wyłącznie czas bieżącej sesji.
    [Tags]    check-transfer    stats
    Attach UE ${VALID_UE_ID}
    Run traffic session for 2s on UE ${VALID_UE_ID} bearer ${DEFAULT_BEARER_ID}
    Restart traffic on UE ${VALID_UE_ID} bearer ${DEFAULT_BEARER_ID} and wait 1s
    Get traffic of UE ${VALID_UE_ID} bearer ${DEFAULT_BEARER_ID}
    Duration should be reset after restart

*** Keywords ***
Reset EPC
    [Documentation]    Przywraca symulator do stanu początkowego przed każdym testem.
    POST On Session    epc    /reset

# --- Akcje domenowe (embedded arguments) ---

Attach UE ${ue_id}
    [Documentation]    Podłącza UE (helper do przygotowania stanu).
    ${body}=    Create Dictionary    ue_id=${ue_id}
    POST On Session    epc    /ues    json=${body}    expected_status=any

Start traffic on UE ${ue_id} bearer ${bearer_id}
    [Documentation]    Rozpoczyna transfer na bearerze (helper do przygotowania stanu, aby był ruch).
    ${body}=    Create Dictionary    protocol=${VALID_PROTOCOL}    Mbps=${VALID_MBPS}
    POST On Session    epc    /ues/${ue_id}/bearers/${bearer_id}/traffic
    ...    json=${body}    expected_status=any

Get traffic of UE ${ue_id} bearer ${bearer_id}
    [Documentation]    Wysyła GET /ues/{ue_id}/bearers/{bearer_id}/traffic i zapisuje odpowiedź w ${LAST_RESPONSE}.
    ${response}=    GET On Session    epc    /ues/${ue_id}/bearers/${bearer_id}/traffic    expected_status=any
    Set Test Variable    ${LAST_RESPONSE}    ${response}

Get aggregated stats for all UEs
    [Documentation]    Wysyła GET /ues/stats (bez parametrów) i zapisuje odpowiedź w ${LAST_RESPONSE}.
    ${response}=    GET On Session    epc    /ues/stats    expected_status=any
    Set Test Variable    ${LAST_RESPONSE}    ${response}

Get aggregated stats for UE ${ue_id}
    [Documentation]    Wysyła GET /ues/stats?ue_id=... i zapisuje odpowiedź w ${LAST_RESPONSE}.
    ${params}=    Create Dictionary    ue_id=${ue_id}
    ${response}=    GET On Session    epc    /ues/stats    params=${params}    expected_status=any
    Set Test Variable    ${LAST_RESPONSE}    ${response}

Get aggregated stats with details for UE ${ue_id}
    [Documentation]    Wysyła GET /ues/stats?ue_id=...&include_details=true i zapisuje odpowiedź w ${LAST_RESPONSE}.
    ${params}=    Create Dictionary    ue_id=${ue_id}    include_details=true
    ${response}=    GET On Session    epc    /ues/stats    params=${params}    expected_status=any
    Set Test Variable    ${LAST_RESPONSE}    ${response}

Get aggregated stats for UE ${ue_id} in unit ${unit}
    [Documentation]    Wysyła GET /ues/stats?ue_id=...&unit=... (wg spec procedura przyjmuje parametr unit) i zapisuje odpowiedź w ${LAST_RESPONSE}.
    ${params}=    Create Dictionary    ue_id=${ue_id}    unit=${unit}
    ${response}=    GET On Session    epc    /ues/stats    params=${params}    expected_status=any
    Set Test Variable    ${LAST_RESPONSE}    ${response}

# --- Asercje domenowe (embedded arguments) ---

Traffic stats should report UE ${ue_id} bearer ${bearer_id}
    [Documentation]    Weryfikuje, że odpowiedź per-bearer zwróciła 200 i raportuje podane UE oraz bearer.
    Status Should Be               200    ${LAST_RESPONSE}
    Should Be Equal As Integers    ${LAST_RESPONSE.json()}[ue_id]        ${ue_id}
    Should Be Equal As Integers    ${LAST_RESPONSE.json()}[bearer_id]    ${bearer_id}

Aggregated stats scope should be ${scope}
    [Documentation]    Weryfikuje, że odpowiedź sumaryczna zwróciła 200 i ma podany zasięg (scope).
    Status Should Be              200    ${LAST_RESPONSE}
    Should Be Equal As Strings    ${LAST_RESPONSE.json()}[scope]    ${scope}

Aggregated stats details should contain UE ${ue_id} bearer ${bearer_id}
    [Documentation]    Weryfikuje, że pole details zawiera rozbicie dla podanego UE i bearera.
    ${ue_key}=        Convert To String    ${ue_id}
    ${bearer_key}=    Convert To String    ${bearer_id}
    Dictionary Should Contain Key    ${LAST_RESPONSE.json()}[details]                ${ue_key}
    Dictionary Should Contain Key    ${LAST_RESPONSE.json()}[details][${ue_key}]    ${bearer_key}

Aggregated stats should report values in unit ${unit}
    [Documentation]    Weryfikuje wg spec, że odpowiedź raportuje wartości transferu w podanej jednostce (domyślną jednostką jest kbps).
    Status Should Be    200    ${LAST_RESPONSE}
    Dictionary Should Contain Key    ${LAST_RESPONSE.json()}    total_tx_${unit}
    Dictionary Should Contain Key    ${LAST_RESPONSE.json()}    total_rx_${unit}

Getting traffic of UE ${ue_id} bearer ${bearer_id} should be rejected
    [Documentation]    Próbuje sprawdzić transfer bearera i weryfikuje, że API zwróciło błąd (status >= 400).
    Get traffic of UE ${ue_id} bearer ${bearer_id}
    Should Be True    ${LAST_RESPONSE.status_code} >= 400
    ...    Sprawdzenie transferu UE=${ue_id} bearer=${bearer_id} powinno zostać odrzucone, a API zwróciło ${LAST_RESPONSE.status_code}

Getting traffic of UE ${ue_id} bearer ${bearer_id} should be rejected with message "${substring}"
    [Documentation]    Jak wyżej, ale dodatkowo sprawdza fragment komunikatu błędu.
    Getting traffic of UE ${ue_id} bearer ${bearer_id} should be rejected
    Should Contain    ${LAST_RESPONSE.text}    ${substring}

Getting aggregated stats for UE ${ue_id} should be rejected
    [Documentation]    Próbuje sprawdzić sumaryczny transfer i weryfikuje, że API zwróciło błąd (status >= 400).
    Get aggregated stats for UE ${ue_id}
    Should Be True    ${LAST_RESPONSE.status_code} >= 400
    ...    Sprawdzenie sumarycznego transferu UE=${ue_id} powinno zostać odrzucone, a API zwróciło ${LAST_RESPONSE.status_code}

Getting aggregated stats for UE ${ue_id} should be rejected with message "${substring}"
    [Documentation]    Jak wyżej, ale dodatkowo sprawdza fragment komunikatu błędu.
    Getting aggregated stats for UE ${ue_id} should be rejected
    Should Contain    ${LAST_RESPONSE.text}    ${substring}

Add bearer ${bearer_id} to UE ${ue_id}
    [Documentation]    Dodaje dedykowany bearer do UE (helper do przygotowania stanu).
    ${body}=    Create Dictionary    bearer_id=${bearer_id}
    POST On Session    epc    /ues/${ue_id}/bearers    json=${body}    expected_status=any

Run traffic session for ${seconds}s on UE ${ue_id} bearer ${bearer_id}
    [Documentation]    Uruchamia transfer, odczekuje ${seconds} sekund i zatrzymuje.
    ${body}=    Create Dictionary    protocol=${VALID_PROTOCOL}    Mbps=${VALID_MBPS}
    POST On Session    epc    /ues/${ue_id}/bearers/${bearer_id}/traffic
    ...    json=${body}    expected_status=any
    Sleep    ${seconds}s
    DELETE On Session    epc    /ues/${ue_id}/bearers/${bearer_id}/traffic    expected_status=any

Restart traffic on UE ${ue_id} bearer ${bearer_id} and wait 1s
    [Documentation]    Ponownie uruchamia transfer i odczekuje 1 sekundę — po tym czasie
    ...                duration powinno wynosić ~1s jeśli pole jest poprawnie resetowane.
    ${body}=    Create Dictionary    protocol=${VALID_PROTOCOL}    Mbps=${VALID_MBPS}
    POST On Session    epc    /ues/${ue_id}/bearers/${bearer_id}/traffic
    ...    json=${body}    expected_status=any
    Sleep    1s

Aggregated stats bearer_count should be
    [Documentation]    Weryfikuje, że pole bearer_count w GET /ues/stats ma oczekiwaną wartość.
    [Arguments]    ${expected_count}
    Status Should Be               200    ${LAST_RESPONSE}
    Should Be Equal As Integers    ${LAST_RESPONSE.json()}[bearer_count]    ${expected_count}

Duration should be reset after restart
    [Documentation]    Weryfikuje, że duration < 2s po zaledwie 1s drugiej sesji.
    ...                Jeśli duration >= 2, oznacza to że czas poprzedniej sesji się akumuluje.
    Status Should Be    200    ${LAST_RESPONSE}
    ${duration}=    Set Variable    ${LAST_RESPONSE.json()}[duration]
    Should Be True    ${duration} < 2
    ...    duration=${duration}s powinna wynosić ~1s po restarcie (oczekiwano < 2s)
