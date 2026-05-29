*** Settings ***
Documentation    Testy funkcjonalności - dodanie kanału transportowego (bearer) dla UE.
...              - Możliwe jest dodanie dedykowanych bearer-ów dla UE
...              - Procedura wymaga podania UE ID oraz bearer ID
...              - Bearer spoza zakresu (1-9) -> błąd
...              - Bearer już dodany -> błąd
...              - Bearer ID 9 jest domyślnie ustanawiany przy podłączeniu UE
Library          RequestsLibrary
Library          Collections
Suite Setup      Create Session    epc    ${BASE_URL}
Test Setup       Reset EPC

*** Variables ***
${BASE_URL}              http://localhost:8000
${VALID_UE_ID}           ${50}
${DEFAULT_BEARER_ID}     ${9}
${VALID_BEARER_ID}       ${1}
${BEARER_ABOVE_RANGE}    ${10}
${BEARER_BELOW_RANGE}    ${0}
${UNATTACHED_UE_ID}      ${77}

*** Test Cases ***
T-080 Adding a valid bearer returns status bearer_added
    [Documentation]    Akcja: dodanie dedykowanego bearera o ID z zakresu 1-9 do podłączonego UE.
    ...                Oczekiwane: 200 ze statusem bearer_added oraz zgodnym UE ID i bearer ID.
    [Tags]    add-bearer    happy-path
    Attach UE ${VALID_UE_ID}
    Add bearer ${VALID_BEARER_ID} to UE ${VALID_UE_ID}
    Add bearer response should confirm UE ${VALID_UE_ID} bearer ${VALID_BEARER_ID}

T-081 Added bearer appears alongside the default bearer in UE state
    [Documentation]    Akcja: dodanie bearera i podgląd stanu UE przez GET /ues/{id}.
    ...                Oczekiwane: nowy bearer pojawia się obok domyślnego bearera 9.
    [Tags]    add-bearer    state
    Attach UE ${VALID_UE_ID}
    Add bearer ${VALID_BEARER_ID} to UE ${VALID_UE_ID}
    UE ${VALID_UE_ID} should have bearers ${VALID_BEARER_ID} and ${DEFAULT_BEARER_ID}

T-082 Adding a bearer above the valid range is rejected
    [Documentation]    Akcja: dodanie bearera o ID = 10 (powyżej zakresu 1-9 zdefiniowanego w kontrakcie).
    ...                Oczekiwane: błąd - procedura wymaga bearer ID z dozwolonego zakresu.
    [Tags]    add-bearer    validation
    Attach UE ${VALID_UE_ID}
    Adding bearer ${BEARER_ABOVE_RANGE} to UE ${VALID_UE_ID} should be rejected with message "Input should be less than or equal to 9"

T-083 Adding a bearer below the valid range is rejected
    [Documentation]    Akcja: dodanie bearera o ID = 0 (poniżej zakresu 1-9 zdefiniowanego w kontrakcie).
    ...                Oczekiwane: błąd - procedura wymaga bearer ID z dozwolonego zakresu.
    [Tags]    add-bearer    validation
    Attach UE ${VALID_UE_ID}
    Adding bearer ${BEARER_BELOW_RANGE} to UE ${VALID_UE_ID} should be rejected with message "Input should be greater than or equal to 1"

T-084 Adding an already-added bearer is rejected
    [Documentation]    Akcja: dwukrotne dodanie tego samego bearera do UE.
    ...                Oczekiwane: drugie dodanie powinno zostać odrzucone - bearer już istnieje.
    [Tags]    add-bearer    conflict
    Attach UE ${VALID_UE_ID}
    Add bearer ${VALID_BEARER_ID} to UE ${VALID_UE_ID}
    Adding bearer ${VALID_BEARER_ID} to UE ${VALID_UE_ID} should be rejected with message "Bearer already exists"

T-085 Adding the default bearer 9 is rejected
    [Documentation]    Akcja: dodanie bearera o ID = 9, który jest domyślnie ustanawiany przy podłączeniu UE.
    ...                Oczekiwane: błąd - bearer 9 już istnieje dla podłączonego UE.
    [Tags]    add-bearer    conflict
    Attach UE ${VALID_UE_ID}
    Adding bearer ${DEFAULT_BEARER_ID} to UE ${VALID_UE_ID} should be rejected with message "Bearer already exists"

T-086 Adding a bearer to an unattached UE is rejected
    [Documentation]    Akcja: dodanie bearera do UE, który nie został przyłączony do sieci.
    ...                Oczekiwane: błąd - procedura wg spec wymaga istniejącego UE ID.
    [Tags]    add-bearer    error
    Adding bearer ${VALID_BEARER_ID} to UE ${UNATTACHED_UE_ID} should be rejected with message "UE not found"

*** Keywords ***
Reset EPC
    [Documentation]    Przywraca symulator do stanu początkowego przed każdym testem.
    POST On Session    epc    /reset

# --- Akcje domenowe (embedded arguments) ---

Attach UE ${ue_id}
    [Documentation]    Podłącza UE (helper do przygotowania stanu).
    ${body}=    Create Dictionary    ue_id=${ue_id}
    POST On Session    epc    /ues    json=${body}    expected_status=any

Add bearer ${bearer_id} to UE ${ue_id}
    [Documentation]    Wysyła POST /ues/{ue_id}/bearers i zapisuje odpowiedź w ${LAST_RESPONSE}.
    ${body}=    Create Dictionary    bearer_id=${bearer_id}
    ${response}=    POST On Session    epc    /ues/${ue_id}/bearers
    ...    json=${body}    expected_status=any
    Set Test Variable    ${LAST_RESPONSE}    ${response}

# --- Asercje domenowe (embedded arguments) ---

Add bearer response should confirm UE ${ue_id} bearer ${bearer_id}
    [Documentation]    Weryfikuje, że ostatnie dodanie bearera zwróciło 200 i body potwierdza UE oraz bearer ID.
    Status Should Be               200    ${LAST_RESPONSE}
    Should Be Equal As Strings     ${LAST_RESPONSE.json()}[status]       bearer_added
    Should Be Equal As Integers    ${LAST_RESPONSE.json()}[ue_id]        ${ue_id}
    Should Be Equal As Integers    ${LAST_RESPONSE.json()}[bearer_id]    ${bearer_id}

UE ${ue_id} should have bearers ${bearer_id} and ${default_bearer_id}
    [Documentation]    Pobiera dane UE i sprawdza, że ma dodany bearer obok domyślnego bearera.
    ${ue}=    GET On Session    epc    /ues/${ue_id}
    Status Should Be    200    ${ue}
    ${key}=            Convert To String    ${bearer_id}
    ${default_key}=    Convert To String    ${default_bearer_id}
    Dictionary Should Contain Key    ${ue.json()}[bearers]    ${key}
    Dictionary Should Contain Key    ${ue.json()}[bearers]    ${default_key}

Adding bearer ${bearer_id} to UE ${ue_id} should be rejected
    [Documentation]    Próbuje dodać bearer i weryfikuje, że API zwróciło błąd (status >= 400).
    Add bearer ${bearer_id} to UE ${ue_id}
    Should Be True    ${LAST_RESPONSE.status_code} >= 400
    ...    Dodanie bearera ${bearer_id} do UE ${ue_id} powinno zostać odrzucone, a API zwróciło ${LAST_RESPONSE.status_code}

Adding bearer ${bearer_id} to UE ${ue_id} should be rejected with message "${substring}"
    [Documentation]    Jak wyżej, ale dodatkowo sprawdza fragment komunikatu błędu.
    Adding bearer ${bearer_id} to UE ${ue_id} should be rejected
    Should Contain    ${LAST_RESPONSE.text}    ${substring}
