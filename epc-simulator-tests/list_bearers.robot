*** Settings ***
Documentation    Testy funkcjonalności - sprawdzenie podłączonych bearer-ów.
...              - Możliwe jest sprawdzenie aktualnie dostępnych bearerów
...              - Procedura wymaga podania UE ID
...              - Podłączony UE udostępnia domyślny bearer ID 9
...              - Dodany dedykowany bearer pojawia się obok domyślnego
...              - Sprawdzenie bearerów nieprzyłączonego UE -> błąd
Library          RequestsLibrary
Library          Collections
Suite Setup      Create Session    epc    ${BASE_URL}
Test Setup       Reset EPC

*** Variables ***
${BASE_URL}                http://localhost:8000
${VALID_UE_ID}             ${50}
${DEFAULT_BEARER_ID}       ${9}
${DEDICATED_BEARER_ID}     ${3}
${UNATTACHED_UE_ID}        ${77}

*** Test Cases ***
T-050 Attached UE exposes the default bearer 9 on its bearer list
    [Documentation]    Akcja: sprawdzenie bearerów podłączonego UE.
    ...                Oczekiwane: 200 oraz lista bearerów zawiera domyślny bearer 9 ustanawiany przy attachu.
    [Tags]    list-bearers    happy-path
    Attach UE ${VALID_UE_ID}
    Get bearers of UE ${VALID_UE_ID}
    UE ${VALID_UE_ID} bearer list should contain bearer ${DEFAULT_BEARER_ID}

T-051 A dedicated bearer appears alongside the default bearer after being added
    [Documentation]    Akcja: dodanie dedykowanego bearera do podłączonego UE i sprawdzenie listy bearerów.
    ...                Oczekiwane: lista bearerów zawiera zarówno domyślny bearer 9, jak i dodany dedykowany bearer.
    [Tags]    list-bearers    state
    Attach UE ${VALID_UE_ID}
    Add bearer ${DEDICATED_BEARER_ID} to UE ${VALID_UE_ID}
    Get bearers of UE ${VALID_UE_ID}
    UE ${VALID_UE_ID} bearer list should contain bearer ${DEFAULT_BEARER_ID}
    UE ${VALID_UE_ID} bearer list should contain bearer ${DEDICATED_BEARER_ID}

T-052 A deleted dedicated bearer disappears from the bearer list
    [Documentation]    Akcja: dodanie i następnie usunięcie dedykowanego bearera, potem sprawdzenie listy bearerów.
    ...                Oczekiwane: usunięty dedykowany bearer znika z listy, domyślny bearer 9 pozostaje dostępny.
    [Tags]    list-bearers    state
    Attach UE ${VALID_UE_ID}
    Add bearer ${DEDICATED_BEARER_ID} to UE ${VALID_UE_ID}
    Delete bearer ${DEDICATED_BEARER_ID} from UE ${VALID_UE_ID}
    Get bearers of UE ${VALID_UE_ID}
    UE ${VALID_UE_ID} bearer list should contain bearer ${DEFAULT_BEARER_ID}
    UE ${VALID_UE_ID} bearer list should not contain bearer ${DEDICATED_BEARER_ID}

T-053 Listing bearers of an unattached UE is rejected
    [Documentation]    Akcja: sprawdzenie bearerów UE, który nie został przyłączony do sieci.
    ...                Oczekiwane: błąd - procedura wg spec wymaga istniejącego UE ID.
    [Tags]    list-bearers    error
    Getting bearers of UE ${UNATTACHED_UE_ID} should be rejected with message "UE not found"

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
    [Documentation]    Dodaje dedykowany bearer do UE (helper do przygotowania stanu).
    ${body}=    Create Dictionary    bearer_id=${bearer_id}
    POST On Session    epc    /ues/${ue_id}/bearers    json=${body}    expected_status=any

Delete bearer ${bearer_id} from UE ${ue_id}
    [Documentation]    Usuwa dedykowany bearer z UE (helper do przygotowania stanu).
    DELETE On Session    epc    /ues/${ue_id}/bearers/${bearer_id}    expected_status=any

Get bearers of UE ${ue_id}
    [Documentation]    Wysyła GET /ues/{id} i zapisuje odpowiedź w ${LAST_RESPONSE}.
    ${response}=    GET On Session    epc    /ues/${ue_id}    expected_status=any
    Set Test Variable    ${LAST_RESPONSE}    ${response}

# --- Asercje domenowe (embedded arguments) ---

UE ${ue_id} bearer list should contain bearer ${bearer_id}
    [Documentation]    Weryfikuje, że ostatni odczyt zwrócił 200 i lista bearerów zawiera dany bearer (klucze to stringi).
    Status Should Be    200    ${LAST_RESPONSE}
    ${key}=    Convert To String    ${bearer_id}
    Dictionary Should Contain Key    ${LAST_RESPONSE.json()}[bearers]    ${key}

UE ${ue_id} bearer list should not contain bearer ${bearer_id}
    [Documentation]    Weryfikuje, że ostatni odczyt zwrócił 200 i lista bearerów nie zawiera danego bearera (klucze to stringi).
    Status Should Be    200    ${LAST_RESPONSE}
    ${key}=    Convert To String    ${bearer_id}
    Dictionary Should Not Contain Key    ${LAST_RESPONSE.json()}[bearers]    ${key}

Getting bearers of UE ${ue_id} should be rejected
    [Documentation]    Próbuje odczytać bearery i weryfikuje, że API zwróciło błąd (status >= 400).
    Get bearers of UE ${ue_id}
    Should Be True    ${LAST_RESPONSE.status_code} >= 400
    ...    Odczyt bearerów UE ${ue_id} powinien zostać odrzucony, a API zwróciło ${LAST_RESPONSE.status_code}

Getting bearers of UE ${ue_id} should be rejected with message "${substring}"
    [Documentation]    Jak wyżej, ale dodatkowo sprawdza fragment komunikatu błędu.
    Getting bearers of UE ${ue_id} should be rejected
    Should Contain    ${LAST_RESPONSE.text}    ${substring}
