*** Settings ***
Documentation    Testy Simple EPC Simulator. Podstawowy smoke test..
Library          RequestsLibrary

*** Variables ***
${BASE_URL}    http://localhost:8000

*** Test Cases ***
API Is Alive
    [Documentation]    Podstawowy smoke test - sprawdza, że API odpowiada na root endpoint.
    [Tags]    smoke
    Create Session    epc    ${BASE_URL}
    ${response}=    GET On Session    epc    /
    Status Should Be    200    ${response}
