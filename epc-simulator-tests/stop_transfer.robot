*** Settings ***
Documentation    Testy funkcjonalności - zakończenie przesyłania danych (stop traffic).
...              - Transfer można zakończyć dla poszczególnego bearera w ramach UE
...              - Transfer można zakończyć całkowicie dla wszystkich bearerów UE
...              - Procedura wymaga podania UE ID oraz opcjonalnie bearer ID
...              - UE nieprzyłączony -> błąd
...              - Bearer nieistniejący -> błąd
Library          RequestsLibrary
Library          Collections
Suite Setup      Create Session    epc    ${BASE_URL}
Test Setup       Reset EPC

*** Variables ***
${BASE_URL}                  http://localhost:8000
${VALID_UE_ID}               ${50}
${DEFAULT_BEARER_ID}         ${9}
${INACTIVE_BEARER_ID}        ${5}
${UNATTACHED_UE_ID}          ${77}
${VALID_MBPS}                ${50}
${VALID_PROTOCOL}            tcp

*** Test Cases ***
T-030 Stopping active traffic returns status traffic_stopped
    [Documentation]    Akcja: zakończenie aktywnego transferu na bearerze 9 dla przyłączonego UE.
    ...                Oczekiwane: 200 ze statusem traffic_stopped oraz zgodnym UE i bearer ID.
    [Tags]    stop-transfer    happy-path
    Attach UE ${VALID_UE_ID}
    Start traffic on UE ${VALID_UE_ID} bearer ${DEFAULT_BEARER_ID}
    Stop traffic on UE ${VALID_UE_ID} bearer ${DEFAULT_BEARER_ID}
    Stop response should confirm UE ${VALID_UE_ID} bearer ${DEFAULT_BEARER_ID}

T-031 Stopped bearer becomes inactive
    [Documentation]    Akcja: zakończenie transferu, a następnie podgląd stanu bearera.
    ...                Oczekiwane: po zatrzymaniu bearer 9 jest nieaktywny (active == False).
    [Tags]    stop-transfer    state
    Attach UE ${VALID_UE_ID}
    Start traffic on UE ${VALID_UE_ID} bearer ${DEFAULT_BEARER_ID}
    Stop traffic on UE ${VALID_UE_ID} bearer ${DEFAULT_BEARER_ID}
    Bearer ${DEFAULT_BEARER_ID} of UE ${VALID_UE_ID} should be inactive

T-032 Stopping an already-stopped bearer is idempotent
    [Documentation]    Akcja: dwukrotne zakończenie transferu na tym samym bearerze.
    ...                Oczekiwane: ponowny stop również zwraca 200 ze statusem traffic_stopped (idempotentny, bez błędu).
    [Tags]    stop-transfer    happy-path
    Attach UE ${VALID_UE_ID}
    Start traffic on UE ${VALID_UE_ID} bearer ${DEFAULT_BEARER_ID}
    Stop traffic on UE ${VALID_UE_ID} bearer ${DEFAULT_BEARER_ID}
    Stop traffic on UE ${VALID_UE_ID} bearer ${DEFAULT_BEARER_ID}
    Stop response should confirm UE ${VALID_UE_ID} bearer ${DEFAULT_BEARER_ID}

T-033 Stopping traffic on an unattached UE is rejected
    [Documentation]    Akcja: zakończenie transferu dla UE, który nie został przyłączony do sieci.
    ...                Oczekiwane: błąd - procedura wg spec wymaga istniejącego UE ID.
    [Tags]    stop-transfer    error
    Stopping traffic on UE ${UNATTACHED_UE_ID} bearer ${DEFAULT_BEARER_ID} should be rejected with message "UE not found"

T-034 Stopping traffic on a non-existent bearer is rejected
    [Documentation]    Akcja: zakończenie transferu na bearerze, który nie został ustanowiony dla UE.
    ...                Oczekiwane: błąd - wg spec procedura wymaga istniejącego bearer ID.
    [Tags]    stop-transfer    error
    Attach UE ${VALID_UE_ID}
    Stopping traffic on UE ${VALID_UE_ID} bearer ${INACTIVE_BEARER_ID} should be rejected with message "Bearer not found"

T-035 Stopping traffic for all bearers of a UE returns success
    [Documentation]    Akcja: zakończenie transferu dla wszystkich bearerów UE (bez podania bearer ID).
    ...                Oczekiwane: wg spec procedura z opcjonalnym bearer ID kończy transfer dla wszystkich bearerów i zwraca sukces.
    [Tags]    stop-transfer    happy-path
    Attach UE ${VALID_UE_ID}
    Start traffic on UE ${VALID_UE_ID} bearer ${DEFAULT_BEARER_ID}
    Stop all traffic on UE ${VALID_UE_ID}
    Stop-all response for UE ${VALID_UE_ID} should succeed

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
    [Documentation]    Rozpoczyna transfer na bearerze (helper do przygotowania stanu).
    ${body}=    Create Dictionary    protocol=${VALID_PROTOCOL}    Mbps=${VALID_MBPS}
    POST On Session    epc    /ues/${ue_id}/bearers/${bearer_id}/traffic
    ...    json=${body}    expected_status=any

Stop traffic on UE ${ue_id} bearer ${bearer_id}
    [Documentation]    Wysyła DELETE /ues/{ue_id}/bearers/{bearer_id}/traffic i zapisuje odpowiedź w ${LAST_RESPONSE}.
    ${response}=    DELETE On Session    epc    /ues/${ue_id}/bearers/${bearer_id}/traffic    expected_status=any
    Set Test Variable    ${LAST_RESPONSE}    ${response}

Stop all traffic on UE ${ue_id}
    [Documentation]    Wysyła DELETE /ues/{ue_id}/traffic (bez bearer ID) i zapisuje odpowiedź w ${LAST_RESPONSE}.
    ${response}=    DELETE On Session    epc    /ues/${ue_id}/traffic    expected_status=any
    Set Test Variable    ${LAST_RESPONSE}    ${response}

# --- Asercje domenowe (embedded arguments) ---

Stop response should confirm UE ${ue_id} bearer ${bearer_id}
    [Documentation]    Weryfikuje, że ostatni stop zwrócił 200 i body potwierdza UE oraz bearer ID.
    Status Should Be               200    ${LAST_RESPONSE}
    Should Be Equal As Strings     ${LAST_RESPONSE.json()}[status]       traffic_stopped
    Should Be Equal As Integers    ${LAST_RESPONSE.json()}[ue_id]        ${ue_id}
    Should Be Equal As Integers    ${LAST_RESPONSE.json()}[bearer_id]    ${bearer_id}

Bearer ${bearer_id} of UE ${ue_id} should be inactive
    [Documentation]    Pobiera dane UE i sprawdza, że bearer jest nieaktywny (active == False).
    ${ue}=    GET On Session    epc    /ues/${ue_id}
    Status Should Be    200    ${ue}
    ${key}=    Convert To String    ${bearer_id}
    Should Be Equal    ${ue.json()}[bearers][${key}][active]    ${False}

Stop-all response for UE ${ue_id} should succeed
    [Documentation]    Weryfikuje, że zakończenie transferu dla wszystkich bearerów UE zwróciło sukces (status 200).
    Status Should Be    200    ${LAST_RESPONSE}

Stopping traffic on UE ${ue_id} bearer ${bearer_id} should be rejected
    [Documentation]    Próbuje stop i weryfikuje, że API zwróciło błąd (status >= 400).
    Stop traffic on UE ${ue_id} bearer ${bearer_id}
    Should Be True    ${LAST_RESPONSE.status_code} >= 400
    ...    Stop traffic UE=${ue_id} bearer=${bearer_id} powinien zostać odrzucony, a API zwróciło ${LAST_RESPONSE.status_code}

Stopping traffic on UE ${ue_id} bearer ${bearer_id} should be rejected with message "${substring}"
    [Documentation]    Jak wyżej, ale dodatkowo sprawdza fragment komunikatu błędu.
    Stopping traffic on UE ${ue_id} bearer ${bearer_id} should be rejected
    Should Contain    ${LAST_RESPONSE.text}    ${substring}
