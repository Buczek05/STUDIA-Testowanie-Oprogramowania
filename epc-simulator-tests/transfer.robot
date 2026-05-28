*** Settings ***
Documentation    Testy funkcjonalności - rozpoczęcie przesyłania danych (start traffic).
...              - Transfer można rozpocząć tylko w kierunku DL (kierunek implicit w API)
...              - Procedura wymaga podania szybkości (Mbps/kbps/bps), UE ID oraz bearer ID
...              - Szybkość spoza zakresu -> błąd
...              - Bearer nieaktywny / nieistniejący -> błąd
...              - Powtórny start na aktywnym bearerze -> błąd
Library          RequestsLibrary
Library          Collections
Suite Setup      Create Session    epc    ${BASE_URL}
Test Setup       Reset EPC

*** Variables ***
${BASE_URL}                  http://localhost:8000
${DEFAULT_BEARER_ID}         ${9}
${INACTIVE_BEARER_ID}        ${5}
${BEARER_ID_BELOW_RANGE}     ${0}
${BEARER_ID_ABOVE_RANGE}     ${10}
${VALID_UE_ID}               ${50}
${UNATTACHED_UE_ID}          ${77}
${VALID_MBPS}                ${100}
${ZERO_MBPS}                 ${0}
${NEGATIVE_MBPS}             ${-1}
${OVER_LIMIT_MBPS}           ${101}
${EXTREME_MBPS}              ${1000000000}
${VALID_PROTOCOL}            tcp

*** Test Cases ***
T-009 Starting traffic with valid parameters returns status traffic_started
    [Documentation]    Akcja: start transferu DL z poprawnym UE, bearer ID i szybkością.
    ...                Oczekiwane: 200 ze statusem traffic_started oraz target_bps zgodnym z przeliczeniem z Mbps.
    [Tags]    transfer    happy-path
    Attach UE ${VALID_UE_ID}
    Start traffic for UE ${VALID_UE_ID} on bearer ${DEFAULT_BEARER_ID} with protocol ${VALID_PROTOCOL} at ${VALID_MBPS} Mbps
    Traffic response should confirm UE ${VALID_UE_ID} on bearer ${DEFAULT_BEARER_ID} with target ${100000000} bps

T-010 Starting traffic without a throughput value is rejected
    [Documentation]    Akcja: start transferu z samym protokołem, bez Mbps/kbps/bps.
    ...                Oczekiwane: błąd - procedura wg spec wymaga podania szybkości transferu.
    [Tags]    transfer    validation
    Attach UE ${VALID_UE_ID}
    Starting traffic without rate for UE ${VALID_UE_ID} on bearer ${DEFAULT_BEARER_ID} should be rejected with message "Provide exactly one throughput value"

T-011 Starting traffic with zero Mbps is rejected
    [Documentation]    Akcja: start transferu z Mbps=0.
    ...                Oczekiwane: błąd - szybkość 0 jest wg spec spoza zakresu.
    [Tags]    transfer    validation    out-of-range
    Attach UE ${VALID_UE_ID}
    Starting traffic for UE ${VALID_UE_ID} on bearer ${DEFAULT_BEARER_ID} with protocol ${VALID_PROTOCOL} at ${ZERO_MBPS} Mbps should be rejected with message "not configured"

T-012 Starting traffic on an inactive (non-existent) bearer is rejected
    [Documentation]    Akcja: start transferu na bearerze, który nie został ustanowiony dla UE.
    ...                Oczekiwane: błąd - wg spec transfer na nieaktywnym bearerze powinien zostać odrzucony.
    [Tags]    transfer    bearer    error
    Attach UE ${VALID_UE_ID}
    Starting traffic for UE ${VALID_UE_ID} on bearer ${INACTIVE_BEARER_ID} with protocol ${VALID_PROTOCOL} at ${VALID_MBPS} Mbps should be rejected with message "Bearer not found"

T-013 Starting traffic on an unattached UE is rejected
    [Documentation]    Akcja: start transferu dla UE, który nie został przyłączony do sieci.
    ...                Oczekiwane: błąd - procedura wg spec wymaga istniejącego UE ID.
    [Tags]    transfer    ue    error
    Starting traffic for UE ${UNATTACHED_UE_ID} on bearer ${DEFAULT_BEARER_ID} with protocol ${VALID_PROTOCOL} at ${VALID_MBPS} Mbps should be rejected with message "UE not found"

T-014 Re-starting traffic on an already-active bearer is rejected
    [Documentation]    Akcja: dwukrotny start transferu na tym samym bearerze, bez zatrzymywania pomiędzy.
    ...                Oczekiwane: drugi start powinien zostać odrzucony - transfer już trwa.
    [Tags]    transfer    conflict
    Attach UE ${VALID_UE_ID}
    Start traffic for UE ${VALID_UE_ID} on bearer ${DEFAULT_BEARER_ID} with protocol ${VALID_PROTOCOL} at ${VALID_MBPS} Mbps
    Starting traffic for UE ${VALID_UE_ID} on bearer ${DEFAULT_BEARER_ID} with protocol ${VALID_PROTOCOL} at ${VALID_MBPS} Mbps should be rejected with message "already running"

T-015 Re-starting traffic after stopping it is allowed
    [Documentation]    Akcja: start transferu, zatrzymanie go, następnie ponowny start na tym samym bearerze.
    ...                Oczekiwane: drugi start powinien się powieść - zatrzymanie nie blokuje ponownego rozpoczęcia transferu.
    [Tags]    transfer    bearer    happy-path
    Attach UE ${VALID_UE_ID}
    Start traffic for UE ${VALID_UE_ID} on bearer ${DEFAULT_BEARER_ID} with protocol ${VALID_PROTOCOL} at ${VALID_MBPS} Mbps
    Stop traffic for UE ${VALID_UE_ID} on bearer ${DEFAULT_BEARER_ID}
    Start traffic for UE ${VALID_UE_ID} on bearer ${DEFAULT_BEARER_ID} with protocol ${VALID_PROTOCOL} at ${VALID_MBPS} Mbps
    Traffic response should confirm UE ${VALID_UE_ID} on bearer ${DEFAULT_BEARER_ID} with target ${100000000} bps

T-016 Starting traffic with negative Mbps is rejected
    [Documentation]    Akcja: start transferu z Mbps=-1.
    ...                Oczekiwane: błąd - szybkość ujemna jest wg spec spoza zakresu.
    [Tags]    transfer    validation    out-of-range
    Attach UE ${VALID_UE_ID}
    Starting traffic for UE ${VALID_UE_ID} on bearer ${DEFAULT_BEARER_ID} with protocol ${VALID_PROTOCOL} at ${NEGATIVE_MBPS} Mbps should be rejected

T-017 Starting traffic with extremely large Mbps is rejected
    [Documentation]    Akcja: start transferu z Mbps=1e9 (1 Pbps - wartość fizycznie nieosiągalna w sieciach LTE/5G).
    ...                Oczekiwane: błąd - szybkość wykracza poza realny zakres wg spec.
    [Tags]    transfer    validation    out-of-range
    Attach UE ${VALID_UE_ID}
    Starting traffic for UE ${VALID_UE_ID} on bearer ${DEFAULT_BEARER_ID} with protocol ${VALID_PROTOCOL} at ${EXTREME_MBPS} Mbps should be rejected

T-018 Starting traffic with multiple throughput fields is rejected
    [Documentation]    Akcja: start transferu z dwoma polami szybkości jednocześnie (Mbps + kbps).
    ...                Oczekiwane: błąd - szybkość powinna być podana w dokładnie jednej jednostce.
    [Tags]    transfer    validation
    Attach UE ${VALID_UE_ID}
    Starting traffic with multiple rates for UE ${VALID_UE_ID} on bearer ${DEFAULT_BEARER_ID} (${100} Mbps + ${50} kbps) should be rejected with message "Provide exactly one throughput value"

T-019 Starting traffic with bearer ID below valid range is rejected
    [Documentation]    Akcja: start transferu z bearer ID = 0 (poniżej zakresu 1-9 zdefiniowanego w kontrakcie).
    ...                Oczekiwane: błąd - procedura wymaga bearer ID z dozwolonego zakresu.
    [Tags]    transfer    bearer    validation
    Attach UE ${VALID_UE_ID}
    Starting traffic for UE ${VALID_UE_ID} on bearer ${BEARER_ID_BELOW_RANGE} with protocol ${VALID_PROTOCOL} at ${VALID_MBPS} Mbps should be rejected

T-020 Starting traffic with bearer ID above valid range is rejected
    [Documentation]    Akcja: start transferu z bearer ID = 10 (powyżej zakresu 1-9 zdefiniowanego w kontrakcie).
    ...                Oczekiwane: błąd - procedura wymaga bearer ID z dozwolonego zakresu.
    [Tags]    transfer    bearer    validation
    Attach UE ${VALID_UE_ID}
    Starting traffic for UE ${VALID_UE_ID} on bearer ${BEARER_ID_ABOVE_RANGE} with protocol ${VALID_PROTOCOL} at ${VALID_MBPS} Mbps should be rejected

T-075 Starting traffic above the 100 Mbps DL limit is rejected
    [Documentation]    Akcja: start transferu z Mbps=101, tuż powyżej limitu ze specyfikacji.
    ...                Oczekiwane: błąd - wg spec maksymalny transfer dla UE w kierunku DL to 100 Mbps.
    [Tags]    transfer    validation    out-of-range
    Attach UE ${VALID_UE_ID}
    Starting traffic for UE ${VALID_UE_ID} on bearer ${DEFAULT_BEARER_ID} with protocol ${VALID_PROTOCOL} at ${OVER_LIMIT_MBPS} Mbps should be rejected

*** Keywords ***
Reset EPC
    [Documentation]    Przywraca symulator do stanu początkowego przed każdym testem.
    POST On Session    epc    /reset

# --- Akcje domenowe (embedded arguments) ---

Attach UE ${ue_id}
    [Documentation]    Podłącza UE (helper do przygotowania stanu).
    ${body}=    Create Dictionary    ue_id=${ue_id}
    POST On Session    epc    /ues    json=${body}    expected_status=any

Start traffic for UE ${ue_id} on bearer ${bearer_id} with protocol ${protocol} at ${mbps} Mbps
    [Documentation]    Wysyła POST /ues/{ue_id}/bearers/{bearer_id}/traffic i zapisuje odpowiedź w ${LAST_RESPONSE}.
    ${body}=    Create Dictionary    protocol=${protocol}    Mbps=${mbps}
    ${response}=    POST On Session    epc    /ues/${ue_id}/bearers/${bearer_id}/traffic
    ...    json=${body}    expected_status=any
    Set Test Variable    ${LAST_RESPONSE}    ${response}

Start traffic without rate for UE ${ue_id} on bearer ${bearer_id}
    [Documentation]    Wysyła start traffic z samym protokołem (bez Mbps/kbps/bps) - oczekiwana walidacja.
    ${body}=    Create Dictionary    protocol=${VALID_PROTOCOL}
    ${response}=    POST On Session    epc    /ues/${ue_id}/bearers/${bearer_id}/traffic
    ...    json=${body}    expected_status=any
    Set Test Variable    ${LAST_RESPONSE}    ${response}

Start traffic with multiple rates for UE ${ue_id} on bearer ${bearer_id} (${mbps} Mbps + ${kbps} kbps)
    [Documentation]    Wysyła start traffic z dwoma polami szybkości jednocześnie - oczekiwana walidacja.
    ${body}=    Create Dictionary    protocol=${VALID_PROTOCOL}    Mbps=${mbps}    kbps=${kbps}
    ${response}=    POST On Session    epc    /ues/${ue_id}/bearers/${bearer_id}/traffic
    ...    json=${body}    expected_status=any
    Set Test Variable    ${LAST_RESPONSE}    ${response}

Stop traffic for UE ${ue_id} on bearer ${bearer_id}
    [Documentation]    Zatrzymuje transfer (helper do przygotowania stanu).
    DELETE On Session    epc    /ues/${ue_id}/bearers/${bearer_id}/traffic    expected_status=any

# --- Asercje domenowe (embedded arguments) ---

Traffic response should confirm UE ${ue_id} on bearer ${bearer_id} with target ${target_bps} bps
    [Documentation]    Weryfikuje, że ostatni start traffic zwrócił 200 i body potwierdza UE, bearer oraz target_bps.
    Status Should Be               200    ${LAST_RESPONSE}
    Should Be Equal As Strings     ${LAST_RESPONSE.json()}[status]       traffic_started
    Should Be Equal As Integers    ${LAST_RESPONSE.json()}[ue_id]        ${ue_id}
    Should Be Equal As Integers    ${LAST_RESPONSE.json()}[bearer_id]    ${bearer_id}
    Should Be Equal As Integers    ${LAST_RESPONSE.json()}[target_bps]   ${target_bps}

Starting traffic for UE ${ue_id} on bearer ${bearer_id} with protocol ${protocol} at ${mbps} Mbps should be rejected
    [Documentation]    Próbuje start traffic i weryfikuje, że API zwróciło błąd (status >= 400).
    Start traffic for UE ${ue_id} on bearer ${bearer_id} with protocol ${protocol} at ${mbps} Mbps
    Should Be True    ${LAST_RESPONSE.status_code} >= 400
    ...    Start traffic UE=${ue_id} bearer=${bearer_id} ${mbps}Mbps powinien zostać odrzucony, a API zwróciło ${LAST_RESPONSE.status_code}

Starting traffic for UE ${ue_id} on bearer ${bearer_id} with protocol ${protocol} at ${mbps} Mbps should be rejected with message "${substring}"
    [Documentation]    Jak wyżej, ale dodatkowo sprawdza fragment komunikatu błędu.
    Starting traffic for UE ${ue_id} on bearer ${bearer_id} with protocol ${protocol} at ${mbps} Mbps should be rejected
    Should Contain    ${LAST_RESPONSE.text}    ${substring}

Starting traffic without rate for UE ${ue_id} on bearer ${bearer_id} should be rejected with message "${substring}"
    [Documentation]    Próbuje start traffic bez rate i weryfikuje błąd walidacji z konkretnym fragmentem komunikatu.
    Start traffic without rate for UE ${ue_id} on bearer ${bearer_id}
    Should Be True    ${LAST_RESPONSE.status_code} >= 400
    ...    Start traffic bez rate UE=${ue_id} bearer=${bearer_id} powinien zostać odrzucony, a API zwróciło ${LAST_RESPONSE.status_code}
    Should Contain    ${LAST_RESPONSE.text}    ${substring}

Starting traffic with multiple rates for UE ${ue_id} on bearer ${bearer_id} (${mbps} Mbps + ${kbps} kbps) should be rejected with message "${substring}"
    [Documentation]    Próbuje start traffic z wieloma polami szybkości i weryfikuje błąd walidacji z konkretnym fragmentem.
    Start traffic with multiple rates for UE ${ue_id} on bearer ${bearer_id} (${mbps} Mbps + ${kbps} kbps)
    Should Be True    ${LAST_RESPONSE.status_code} >= 400
    ...    Start traffic UE=${ue_id} bearer=${bearer_id} z wieloma rate powinien zostać odrzucony, a API zwróciło ${LAST_RESPONSE.status_code}
    Should Contain    ${LAST_RESPONSE.text}    ${substring}
